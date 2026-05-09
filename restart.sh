#!/bin/bash
echo "Starting cluster..."
DOCKER_DEFAULT_PLATFORM=linux/amd64 docker compose up -d
echo "Waiting 60s for startup..."
sleep 60
echo "Fixing memory settings..."
docker exec -it nodemanager bash -c "sed -i 's|<value>4096</value>|<value>512</value>|g' /opt/hadoop/etc/hadoop/mapred-site.xml && sed -i 's|<value>8192</value>|<value>512</value>|g' /opt/hadoop/etc/hadoop/mapred-site.xml && sed -i 's|<value>3072</value>|<value>400</value>|g' /opt/hadoop/etc/hadoop/mapred-site.xml && sed -i 's|<value>6144</value>|<value>400</value>|g' /opt/hadoop/etc/hadoop/mapred-site.xml"
docker exec -it namenode bash -c "sed -i 's|<value>4096</value>|<value>512</value>|g' /opt/hadoop/etc/hadoop/mapred-site.xml && sed -i 's|<value>8192</value>|<value>512</value>|g' /opt/hadoop/etc/hadoop/mapred-site.xml && sed -i 's|<value>3072</value>|<value>400</value>|g' /opt/hadoop/etc/hadoop/mapred-site.xml && sed -i 's|<value>6144</value>|<value>400</value>|g' /opt/hadoop/etc/hadoop/mapred-site.xml"
docker exec -it namenode bash -c "sed -i 's/hadoop-3.3.5/hadoop-3.4.0/g' /opt/hadoop/etc/hadoop/mapred-site.xml"
docker exec -it nodemanager bash -c "sed -i 's/hadoop-3.3.5/hadoop-3.4.0/g' /opt/hadoop/etc/hadoop/mapred-site.xml"
echo "Ready! Run: docker exec -it namenode bash"
