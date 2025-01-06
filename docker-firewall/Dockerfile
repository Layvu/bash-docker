FROM ubuntu:20.04

# Устанавливаем необходимые пакеты для работы с сетью и фаерволом
RUN apt-get update && \
    apt-get install -y iproute2 iptables curl dnsutils iputils-ping && \
    apt-get clean

# Отключаем IPv6
RUN echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf

WORKDIR /app

# Копируем файлы ресурсов и скрипты
COPY resources.txt /app/resources.txt
COPY setup-firewall.sh /app/setup-firewall.sh
RUN chmod +x /app/setup-firewall.sh

# Запуск контейнера с выполнением скрипта и удержанием контейнера активным
CMD ["/bin/bash", "-c", "/app/setup-firewall.sh && tail -f /dev/null"]
