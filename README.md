## Install

```
% heroku plugins:install git@github.com:heroku/heroku-log-analyze.git
```

## Use

```
% heroku logs:analyze -a dashboard

Data processed: 54 seconds

RPM:          53
Median:      300 ms
P95:        1162 ms
P99:        1451 ms
Max:        1451 ms

Requests by Status Code

200:          43
302:           5
Total:        48
```
