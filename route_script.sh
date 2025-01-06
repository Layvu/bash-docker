#!/bin/bash

# Проверяем, передан ли файл через консоль
if [ -z "$1" ]; then
  echo "Ошибка: укажите файл с ресурсами при запуске скрипта."
  echo "Пример: $0 <filename>"
  exit 1
fi

INPUT_FILE="$1"

# Проверка существования файла с ресурсами
if [ ! -f "$INPUT_FILE" ]; then
    echo "Файл $INPUT_FILE не найден"
    exit 1
fi



# Инициализация переменных
VPN_IF=""
REMOVE_VPN=false

# Проверка наличия активного VPN-интерфейса (tun0, ppp0, wg0, ...)
for iface in $(ip link show | awk -F': ' '{print $2}'); do
    if [[ "$iface" =~ ^(tun|ppp|wg|tap|sl|vxlan|gre|ipsec|stf|erspan|geneve|vti|xfrm)[0-9]+$ ]]; then
        if ip link show "$iface" | grep -q "state UP"; then
            VPN_IF=$iface
            break
        fi
    fi
done

# Если VPN-интерфейс не найден, создаём эмуляцию VPN через интерфейс dummy (для теста)
if [ -z "$VPN_IF" ]; then
    echo "VPN-соединение не найдено. Создаю эмуляцию VPN через интерфейс vpn0"
    VPN_IF="vpn0"
    ip link add $VPN_IF type dummy
    ip addr add 10.0.0.1/24 dev $VPN_IF
    ip link set $VPN_IF up
    REMOVE_VPN=true
else
    echo "Используем существующий VPN-интерфейс: $VPN_IF"
fi



# Проверяем наличие дефолтного маршрута через VPN
default_vpn_route=$(ip route show | grep "^default .* dev $VPN_IF")

if [ -n "$default_vpn_route" ]; then
    echo "Обнаружен дефолтный маршрут через VPN ($VPN_IF): $default_vpn_route"
    echo "Удаляю дефолтный маршрут через $VPN_IF"
    ip route del default dev "$VPN_IF" || echo "Ошибка удаления дефолтного маршрута через $VPN_IF"
else
    echo "Дефолтный маршрут через $VPN_IF не найден"
fi



# Определение активного физического интерфейса. Для маршрутов по умолчанию

# Получаем список всех интерфейсов, исключая loopback и VPN
INTERFACES=$(ip link show | awk -F': ' '{print $2}' | grep -Ev "lo|$VPN_IF")

# Перебираем физические интерфейсы и проверяем подключение к интернету
PHYS_IF=""
for iface in $INTERFACES; do
    if ip link show "$iface" | grep -q 'state UP'; then
        echo "Проверяю доступность интернета через $iface"
        if ping -c 1 -I "$iface" 8.8.8.8 >/dev/null 2>&1; then
            PHYS_IF=$iface
            echo "Интернет доступен через $iface"
            break
        fi
    fi
done
# Если не нашли такой интерфейс
if [ -z "$PHYS_IF" ]; then
    echo "Не удалось найти активный физический интерфейс"
    [[ "$REMOVE_VPN" == true ]] && ip link delete "$VPN_IF"
    exit 1
fi
echo "Активный физический интерфейс: $PHYS_IF"



# Удаление старых маршрутов
echo "Удаляю маршруты для ресурсов из $INPUT_FILE"
while IFS= read -r resource; do
    # Проверяем является ли ресурс IP
    if [[ $resource =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ip_address=$resource
    else
        # Если это URL, пытаемся его резолвить в IP
        ip_addresses=$(getent ahosts "$resource" | awk '$1 ~ /^[0-9]+\./ {print $1}' | sort -u)

        if [ -n "$ip_addresses" ]; then
            for ip_address in $ip_addresses; do
                echo "Удаляю маршрут для $ip_address"
                ip route del "$ip_address" 2>/dev/null
            done
        else
            echo "Не удалось резолвить $resource. Пропускаю."
        fi
    fi
    if [ -n "$ip_address" ]; then
        ip route del "$ip_address" 2>/dev/null
    fi
done < "$INPUT_FILE"



# Установка маршрутов для каждого ресурса из файла

echo "Начинаю добавлять маршруты для ресурсов из $INPUT_FILE"
while IFS= read -r resource; do
    # Проверяем, является ли ресурс IP
    if [[ $resource =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ip_addresses=$resource
        echo "Обрабатываю IP: $resource"
    else
        # Если это URL, пытаемся его резолвить в IP
        echo "Пытаюсь резолвить URL: $resource"
        ip_addresses=$(getent ahosts "$resource" | awk '$1 ~ /^[0-9]+\./ {print $1}' | sort -u)
        
        # Если не удается резолвить, выводим ошибку
        if [ -z "$ip_addresses" ]; then
            echo "Не удалось резолвить $resource. Проверьте подключение к сети или DNS"
            continue
        fi
        echo "URL $resource резолвится в IP: $ip_addresses"
    fi

    # Обрабатываем каждый IP-адрес, связанный с ресурсом
    for ip_address in $ip_addresses; do
        echo "Обрабатываю IP $ip_address для $resource"

        # Проверяем, существует ли уже маршрут для этого IP
        if ! ip route show | grep -q "$ip_address"; then
            # Если маршрута нет, добавляем его через VPN
            echo "Добавляю маршрут для $ip_address через $VPN_IF"
            ip route add "$ip_address" dev "$VPN_IF" || echo "Ошибка добавления маршрута для $resource ($ip_address)"
        else
            echo "Маршрут для $resource ($ip_address) уже существует"
        fi
    done
done < "$INPUT_FILE"



# Добавляем маршрут по умолчанию через физический интерфейс, если он ещё не настроен
if ! ip route show | grep -q "default"; then
    echo "Добавляю маршрут по умолчанию через $PHYS_IF"
    ip route add default dev "$PHYS_IF" || echo "Ошибка добавления маршрута по умолчанию"
else
    echo "Маршрут по умолчанию уже существует"
fi



echo "Маршруты настроены"

# Вывод всех текущих маршрутов
echo "Текущие маршруты:"
ip route show

# Удаление VPN-интерфейса для теста скрипта
if [[ "$REMOVE_VPN" == true ]]; then
    echo "Удаляю VPN-интерфейс $VPN_IF"
    ip link delete "$VPN_IF"
fi

echo "Скрипт завершён"


#  ./route_script.sh resources.txt

#  ip route show