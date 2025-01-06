#!/bin/bash

# Отключение IPv6
echo "Отключаем IPv6..."
sysctl -w net.ipv6.conf.all.disable_ipv6=1

# Очистка текущих правил iptables
echo "Очищаем текущие правила iptables..."
iptables -F

# Установка политики по умолчанию
echo "Устанавливаем политику по умолчанию на DROP для INPUT..."
iptables -P INPUT DROP
iptables -P OUTPUT ACCEPT
iptables -P FORWARD ACCEPT

# Разрешение локального трафика
echo "Разрешаем локальный трафик..."
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Разрешение исходящих соединений для уже установленных соединений
echo "Разрешаем уже установленные соединения..."
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Разрешение ICMP (для пингов)
echo "Разрешаем ICMP-запросы (пинги)..."
iptables -A OUTPUT -p icmp --icmp-type 8 -j ACCEPT
iptables -A INPUT -p icmp --icmp-type 0 -j ACCEPT

# Разрешаем исходящие соединения на все IP-адреса
echo "Разрешаем исходящие соединения на все IP-адреса..."
iptables -A OUTPUT -o eth0 -j ACCEPT

# Разрешаем исходящие DNS-запросы
echo "Разрешаем исходящие DNS-запросы (порт 53)..."
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT

# Разрешаем HTTP/HTTPS-запросы (порт 80 и 443)
echo "Разрешаем исходящие HTTP/HTTPS-запросы (порты 80 и 443)..."
iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT

# Чтение ресурсов из файла resources.txt и разрешение доступа
echo "Читаем ресурсы из файла resources.txt..."
while IFS= read -r resource; do
    # Пропускаем пустые строки
    if [[ -z "$resource" || "$resource" =~ ^[[:space:]]*$ ]]; then
        continue
    fi

    # Разрешаем только домены, а не IP-адреса
    if [[ "$resource" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Пропускаем IP-адрес $resource, разрешение только для доменных имен."
        continue
    fi

    # Получаем IP-адрес из доменного имени
    ip=$(dig +short "$resource")
    if [ -n "$ip" ]; then
        echo "Разрешаем доступ к IP: $ip"
        iptables -A INPUT -p tcp -s "$ip" -j ACCEPT
        iptables -A OUTPUT -p tcp -d "$ip" -j ACCEPT
    else
        echo "Не удалось разрешить ресурс $resource"
    fi
done < /app/resources.txt

# Журналируем все заблокированные соединения
echo "Настроим журналирование заблокированных соединений..."
iptables -A INPUT -j LOG --log-prefix "INPUT_DROP: " --log-level 4
iptables -A OUTPUT -j LOG --log-prefix "OUTPUT_DROP: " --log-level 4

# Блокируем все остальные подключения
echo "Блокируем все остальные подключения, которые не прошли через разрешенные правила..."
iptables -A INPUT -j DROP
iptables -A OUTPUT -j DROP

echo "Фаервол настроен. Доступ разрешен только к ресурсам из resources.txt."
