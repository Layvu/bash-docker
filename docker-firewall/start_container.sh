#!/bin/bash

# Проверка наличия и удаление существующего контейнера
if docker ps -aq -f name=my_firewall_container > /dev/null; then
    echo "Контейнер my_firewall_container уже существует. Удаляем..."
    docker stop my_firewall_container && docker rm -f my_firewall_container
    echo "Контейнер удален."
fi

# Создание Docker-образа
echo "Создание Docker-образа..."
docker build -t my_firewall_image .

# Запуск контейнера
echo "Запуск контейнера..."
docker run --name my_firewall_container --privileged --network bridge --dns 8.8.8.8 --dns 8.8.4.4 -d my_firewall_image

# Проверка запуска контейнера
if [ $? -ne 0 ]; then
    echo "Ошибка: контейнер не удалось запустить."
    exit 1
fi

echo "Контейнер успешно запущен."

# Ожидание запуска контейнера
MAX_RETRIES=10
COUNT=0
while ! docker exec my_firewall_container ps aux > /dev/null 2>&1; do
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "Ошибка: контейнер не отвечает."
        exit 1
    fi
    echo "Ожидание запуска контейнера..."
    sleep 2
    COUNT=$((COUNT + 1))
done


# Проверка DNS
echo "Проверка разрешения DNS..."
resources=("github.com" "www.google.com")
for resource in "${resources[@]}"; do
    resolved_ip=$(docker exec my_firewall_container getent ahosts "$resource" | awk '{print $1}' | head -n 1)
    if [ -z "$resolved_ip" ]; then
        echo " - Ошибка: домен $resource не резолвится."
    else
        echo " - $resource резолвится в $resolved_ip."
    fi
done

# Проверка доступности ресурсов
if [ ! -f ./resources.txt ]; then
    echo "Ошибка: файл resources.txt не найден!"
    exit 1
fi

echo "Проверка доступности ресурсов..."
while IFS= read -r resource; do
    [[ -z "$resource" || "$resource" =~ ^[[:space:]]*$ ]] && continue
    echo "Проверка ресурса: $resource"

    if [[ "$resource" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        docker exec my_firewall_container ping -c 3 -W 15 "$resource" &> /dev/null
        if [ $? -eq 0 ]; then
            echo " - $resource доступен."
        else
            echo " - $resource недоступен."
        fi
    else
        resolved_ip=$(docker exec my_firewall_container getent ahosts "$resource" | awk '{print $1}' | head -n 1)
        if [ -z "$resolved_ip" ]; then
            echo " - Ошибка: домен $resource не резолвится."
        else
            docker exec my_firewall_container ping -c 3 -W 15 "$resolved_ip" &> /dev/null
            if [ $? -eq 0 ]; then
                echo " - $resource ($resolved_ip) доступен."
            else
                echo " - $resource ($resolved_ip) недоступен."
            fi
        fi
    fi
done < ./resources.txt

# Тесты HTTP/HTTPS
declare -A urls
urls["https://github.com"]="разрешён"
urls["http://github.com"]="разрешён"
urls["https://example.com"]="заблокирован"
urls["http://example.com"]="заблокирован"

echo "Проверка HTTP/HTTPS запросов..."
for url in "${!urls[@]}"; do 
    status=$(docker exec my_firewall_container curl -I -m 5 -s -o /dev/null -w "%{http_code}" -k "$url")
    
    # Добавление проверки для 301 (редирект)
    if [[ "$status" -ge 200 && "$status" -lt 400 || "$status" -eq 301 ]]; then
        echo " - $url доступен (${urls[$url]})."
    else
        echo " - $url недоступен (${urls[$url]}). Статус: $status"
    fi
done

# Завершение
echo "Все тесты завершены."



# ./start_container.sh



# cd docker-firewall

# docker exec -it my_firewall_container bash

# iptables -L -n

# разрешённые:
# ping -c 3 8.8.8.8 
# ping -c 3 1.1.1.1
# ping -c 3 github.com
# ping -c 3 173.194.73.99

# заблокированные:
# ping -c 3 example.com
# ping -c 3 192.168.0.1

# Первый разрешён, второй запрещён
# http:
# curl -I -w "%{http_code}" http://github.com
# curl -I -m 5 -w "%{http_code}" http://example.com
# https:
# curl -I -w "%{http_code}" -k https://github.com
# curl -I -m 5 -w "%{http_code}" -k https://example.com 
