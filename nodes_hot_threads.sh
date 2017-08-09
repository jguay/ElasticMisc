#takes node hot threads data every minutes
for run in {1..20}
do
  curl -u elastic:changeme -XGET "http://localhost:9200/_nodes/hot_threads?threads=10&interval=500ms" > hot_threads_cpu_$(date "+%H-%M-%S").log
  curl -u elastic:changeme -XGET "http://localhost:9200/_nodes/hot_threads?threads=10&interval=500ms&type=block" > hot_threads_block_$(date "+%H-%M-%S").log
  curl -u elastic:changeme -XGET "http://localhost:9200/_nodes/hot_threads?threads=10&interval=500ms&type=wait" > hot_threads_wait_$(date "+%H-%M-%S").log
  sleep 60
done
