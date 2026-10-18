FROM hagb/docker-atrust:latest

COPY atrust.deb /tmp/atrust.deb

RUN (dpkg -i /tmp/atrust.deb || apt-get install -f -y) && \
    rm -f /tmp/atrust.deb && \
    if [ -e /home/sangfor/ ]; then chown sangfor:sangfor -R /home/sangfor/; fi && \
    ln -fs /bin/false /usr/sbin/dmidecode && \
    mkdir -p /usr/share/sangfor/.aTrust/var/conf && \
    printf '{"lang":"zh-CN"}\n' > /usr/share/sangfor/.aTrust/var/conf/localConfig.json && \
    chmod 666 /usr/share/sangfor/.aTrust/var/conf/localConfig.json && \
    printf '#!/bin/sh\nexec sleep infinity\n' > /usr/share/sangfor/aTrust/resources/bin/aTrustTray2 && \
    chmod +x /usr/share/sangfor/aTrust/resources/bin/aTrustTray2

# 将 SOCKS5 改为 21080，HTTP 改为 28888
RUN sed -i 's/1080/21080/g' /usr/local/bin/start.sh && \
    sed -i 's/8888/28888/g' /etc/tinyproxy.conf /usr/local/bin/start.sh && \
    sed -i 's/VPN_PROCS=aTrustAgent/VPN_PROCS=\\"aTrustAgent aTrustTray\\"/g' /usr/local/bin/vpn-config.sh
