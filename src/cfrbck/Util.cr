module Util
  class SimpleProgress
    def initialize(total)
      @total= total
      @onep = total / 100.0
      @onep = 1 if @onep < 1
      @next_tick = @onep
      @processed_count = 0
      @bar = ProgressBar.new
      @bar.total = 100
    end

    def update(delta)
      @processed_count += delta
      if @processed_count < @total
        if @processed_count > @next_tick
          @next_tick += @onep
          @bar.inc
        end
      end
    end

    def done
      @bar.done
    end
  end
end
