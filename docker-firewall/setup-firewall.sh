#!/bin/bash

set -e

# Отключение IPv6
echo "Отключение IPv6..."
sysctl -w net.ipv6.conf.all.disable_ipv6=1 > /dev/null

# Очистка текущих правил
echo "Очистка текущих правил iptables..."
iptables -F
iptables -X

# Установка политики по умолчанию
echo "Установка политики по умолчанию..."
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

# Разрешение локального трафика
echo "Разрешение локального трафика..."
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Разрешение установленных соединений
echo "Разрешение установленных соединений..."
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Разрешение DNS-запросов
echo "Разрешение DNS-запросов..."
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A INPUT -p tcp --sport 53 -j ACCEPT

# Проверка наличия файла ресурсов
echo "Обработка файла ресурсов..."
if [[ ! -f /app/resources.txt ]]; then
    echo "Ошибка: файл /app/resources.txt не найден!"
    exit 1
fi

# Список уже обработанных IP-адресов
processed_ips=()

while IFS= read -r resource; do
    [[ -z "$resource" || "$resource" =~ ^[[:space:]]*$ ]] && continue

    if [[ "$resource" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # IP-адрес
        if [[ ! " ${processed_ips[*]} " =~ " $resource " ]]; then
            echo "Разрешение доступа к IP $resource"
            iptables -A INPUT -s "$resource" -j ACCEPT
            iptables -A OUTPUT -d "$resource" -j ACCEPT
            # Разрешение HTTP и HTTPS для данного IP-адреса
            iptables -A OUTPUT -d "$resource" -p tcp --dport 80 -j ACCEPT
            iptables -A OUTPUT -d "$resource" -p tcp --dport 443 -j ACCEPT
            iptables -A INPUT -s "$resource" -p tcp --sport 80 -j ACCEPT
            iptables -A INPUT -s "$resource" -p tcp --sport 443 -j ACCEPT
            processed_ips+=("$resource")
        fi
    else
        # Доменное имя
        echo "Резолвинг домена $resource..."
        ip_list=$(getent ahosts "$resource" | awk '{print $1}' | uniq | grep -Eo '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
        if [[ -z "$ip_list" ]]; then
            echo "Ошибка: домен $resource не удалось резолвить в IP. Пропуск."
            continue
        fi
        for ip in $ip_list; do
            if [[ ! " ${processed_ips[*]} " =~ " $ip " ]]; then
                echo " - Разрешение доступа к IP $ip ($resource)"
                iptables -A INPUT -s "$ip" -j ACCEPT
                iptables -A OUTPUT -d "$ip" -j ACCEPT
                # Разрешение HTTP и HTTPS для данного IP-адреса
                iptables -A OUTPUT -d "$ip" -p tcp --dport 80 -j ACCEPT
                iptables -A OUTPUT -d "$ip" -p tcp --dport 443 -j ACCEPT
                iptables -A INPUT -s "$ip" -p tcp --sport 80 -j ACCEPT
                iptables -A INPUT -s "$ip" -p tcp --sport 443 -j ACCEPT
                processed_ips+=("$ip")
            fi
        done
    fi
    sleep 1
done < /app/resources.txt

# Блокировка всего остального
echo "Блокировка всего остального завершена. Политики DROP по умолчанию активны."
echo "Настройка завершена успешно!"




# docker logs my_firewall_container
