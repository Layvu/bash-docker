#!/bin/bash

# Проверяем, существует ли контейнер с именем my_firewall_container
if [ "$(docker ps -aq -f name=my_firewall_container)" ]; then
    echo "Контейнер my_firewall_container уже существует. Останавливаем и удаляем его..."
    
    # Останавливаем контейнер перед удалением
    docker stop my_firewall_container
    docker rm -f my_firewall_container
    
    echo "Контейнер удален."
fi

# Создаем Docker образ
echo "Создаем Docker образ..."
docker build -t my_firewall_image .

# Запускаем контейнер с созданным образом, с правами суперпользователя для работы iptables
echo "Запускаем контейнер..."
docker run --name my_firewall_container --privileged --network bridge --dns 8.8.8.8 --dns 8.8.4.4 -d my_firewall_image

echo "Контейнер запущен."

# Ждем завершения настройки файрвола
sleep 5

# Проверяем маршрутизацию внутри контейнера
echo "Проверка маршрутизации внутри контейнера..."
docker exec my_firewall_container ip route

# Проверяем правила iptables внутри контейнера
echo "Проверка правил iptables:"
docker exec my_firewall_container iptables -L -n

# Проверяем доступ к ресурсам из resources.txt
if [ ! -f ./resources.txt ]; then
    echo "Файл resources.txt не найден!"
    exit 1
fi

# Проверка доступности ресурсов
echo "Проверка доступности ресурсов:"
while IFS= read -r line; do
    if [[ ! "$line" =~ ^[[:space:]]*$ ]]; then  # Пропускаем пустые строки
        echo "Проверка доступа к $line"
        
        # Проверяем доступность ресурса с помощью ping (для IP-адресов)
        if [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            if docker exec my_firewall_container ping -c 1 "$line" &> /dev/null; then
                echo "$line доступен для пинга."
            else
                echo "$line недоступен для пинга."
            fi
        else
            # Проверяем доступность ресурса через HTTP с помощью curl (с поддержкой редиректов)
            if docker exec my_firewall_container ping -c 1 "$line" &> /dev/null; then
                echo "$line доступен для пинга."
                
                # Выполняем HTTP-запрос только для доменных имен
                response=$(docker exec my_firewall_container curl -Ls -o /dev/null -w "%{http_code}" "$line")
                if [ "$response" == "200" ]; then
                    echo "$line доступен (HTTP код 200)."
                elif [[ "$response" == "301" || "$response" == "302" ]]; then
                    echo "$line перенаправляет на другой URL. Код ответа: $response"
                else
                    echo "$line недоступен для HTTP-запросов. Код ответа: $response"
                fi
            else
                echo "$line недоступен для пинга."
            fi
        fi
        
        sleep 2  # Добавляем задержку между проверками
    fi
done < resources.txt

# Диагностика DNS внутри контейнера
echo "Проверка DNS внутри контейнера..."
docker exec my_firewall_container nslookup github.com || echo "Ошибка при разрешении домена github.com."

# Проверка сетевого соединения в контейнере через HTTPS
echo "Тестирование сетевого соединения (HTTPS) с github.com..."
docker exec my_firewall_container curl -s -o /dev/null -w "%{http_code}" https://github.com || echo "Не удается выполнить HTTPS-запрос к github.com."

echo "Проверка завершена."


# ./start_container.sh

# iptables -L -n