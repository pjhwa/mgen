## analyze_mgen.py

Usage: `python3 analyze_mgen.py receiver_srv1.log receiver_srv2.log output.csv`

Result sample:
```
root@k1:~# python3 analyze_mgen.py receiver_k3.log receiver_k4.log output.csv
[ ID] Interval       Transfer     Bandwidth       Jitter    Lost/Total Datagrams
[  1] 0.0-10.0 sec   10.24 MBytes  8.19 Mbits/sec  0.017 ms  0/10001 (0.0%)
[ ID] Interval       Transfer     Bandwidth       Jitter    Lost/Total Datagrams
[  1] 0.0-10.0 sec   10.24 MBytes  8.19 Mbits/sec  0.013 ms  0/10001 (0.0%)
```
