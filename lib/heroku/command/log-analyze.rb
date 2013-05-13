require 'heroku/command/base'
require 'time'
require 'net/http'

class Heroku::Command::Logs < Heroku::Command::Base

  def analyze
    exit unless $stdout.tty?

    puts "Receiving log data. Please wait for first report."

    @start = get_current_time
    @store = Hash.new do |h,k|
      h[k] = {
        :connect => [],
        :service => [],
        :status => Hash.new { |h1,k1| h1[k1] = 0 },
        :errors => Hash.new { |h1,k1| h1[k1] = 0 }
      }
    end

    Thread.new do
      begin
        heroku.read_logs(app, ["num=0", "tail=1", "source=heroku", "ps=router"]) do |chunk|
          chunk.split("\n").each do |line|
            timestamp, _, data = line.split(/\s+/, 3)
            next unless data
            time = Time.iso8601(timestamp) rescue nil
            next unless time
            _, dyno, connect, service, status = data.match(/dyno=(\S+)\s+connect=(\d+)ms\s+service=(\d+)ms\s+status=(\d+)/).to_a
            if match = data.match(/at=error code=(\S+)/)
              error = match[1]
            else
              error = nil
            end
            store_log_data(time, dyno, connect.to_i, service.to_i, status.to_i, error)
          end
        end
      rescue Exception => e
        p e.inspect
        p e.backtrace
      end
    end

    while true
      report_log_data
      sleep 5
    end

  rescue Interrupt
    # dont print anything on Interrupt
  end

private

  def report_log_data
    seconds = @store.keys.max || 0
    return if seconds == 0

    if @reported
      print "\033[#{@reported}A"
    else
      print "\033[1A\033[K"
    end

    aggregated = aggregate_data
    return if aggregated.nil?

    sv, st, err = aggregated[:service], aggregated[:status], aggregated[:errors]

    count = sv.size
    rpm = (count * 60 / seconds).round

    print template % [seconds, rpm, sv[count / 2], sv[count * 19 / 20], sv[count * 99 / 100], sv.last]
    print "\n"

    print "Requests by Status Code\n\n"

    st.to_a.sort.each do |(k, v)|
      print "%3d:   %9d\n" % [k, v]
    end
    print "Total: %9d\n" % [count]

    if err.size > 0
      print "\nHeroku Errors\n\n"
      err.to_a.sort.each do |(k, v)|
        print "%3s:   %9d\n" % [k, v]
      end
    end

    @reported = err.size + st.size + 12 + (err.size > 0 ? 3 : 0)
  end

  def store_log_data(time, dyno, connect, service, status, error)
    t = (time - @start).round
    return if t < 0 || dyno.nil?
    #@store[t][:connect] << connect
    Thread.exclusive do
      @store[t][:service] << service
      @store[t][:status][status] += 1
      @store[t][:errors][error] += 1 if error
    end
  end

  def aggregate_data
    aggregated = @store.values.inject do |a, b|
      h = {
        #connect: a[:connect] + b[:connect],
        :service => a[:service] + b[:service],
        :status => a[:status].dup,
        :errors => a[:errors].dup
      }
      b[:status].each { |k,v| h[:status][k] += v }
      b[:errors].each { |k,v| h[:errors][k] += v }
      h
    end
    if aggregated
      aggregated[:service].sort!
      #aggregated[:connect].sort!
    end
    aggregated
  end

  def template
    @template ||= <<-EOF.gsub(/^ +/, '')

      Data processed: %d seconds

      RPM:    %8d
      Median:   %6d ms
      P95:      %6d ms
      P99:      %6d ms
      Max:      %6d ms
    EOF
  end

  def get_current_time
    request = Net::HTTP::Get.new('/')
    request['Accept'] = 'text/plain'
    Time.iso8601(Net::HTTP.new("utc.herokuapp.com", 80).request(request).body)
  end

  def print(stuff)
    $stdout.print stuff.gsub("\n", "\n\033[K")
  end

end
