class BytecodeSpool
  def initialize bytecodes
    @bytecodes = bytecodes + [[:done]]
    @counter = 0
    @label_to_counter = label_to_counter(bytecodes)
    @breakpoint = 'NEXT_POSITION'
    @num_steps_queued = 0
    @is_done = false
    @counter_stack = []
    @last_yourcode_position = []
  end

  def counter # just for debugging prompt
    @counter
  end

  def visible_state
    { breakpoint: @breakpoint,
      num_steps_queued: @num_steps_queued,
      is_done: @is_done }
  end

  def is_done?
    @is_done
  end

  def queue_run_until breakpoint
    if @breakpoint == breakpoint
      @num_steps_queued += 1
    else
      @breakpoint = breakpoint
      @num_steps_queued = 1
    end
  end

  def get_next_bytecode
    if @is_done
      nil
    elsif @counter >= @bytecodes.size
      nil
    elsif @num_steps_queued == 0
      nil
    else
      bytecode = @bytecodes[@counter]
      @num_steps_queued -= 1 if @breakpoint == 'NEXT_BYTECODE'
      case bytecode[0]
        when :position
          if bytecode[1] == 'YourCode'
            line0, col0 = @last_yourcode_position[2..3]
            line1, col1 = [bytecode[2], bytecode[3]]
            if @breakpoint == 'NEXT_POSITION'
              @num_steps_queued -= 1
            elsif @breakpoint == 'NEXT_LINE' && line1 != line0
              @num_steps_queued -= 1
            end
            @last_yourcode_position = bytecode
          end
        when :done
          @num_steps_queued = 0
          @is_done = true
      end
      @counter += 1 # ok to step past label
      bytecode
    end
  end

  def do_command command, *args
    case command
      when 'GOTO'
        label = args[0]
        @counter = @label_to_counter[label] or raise "Can't find label #{label}"
      when 'RESCUE'
        # subtract one because method_stack has an entry for the current
        # line number; whereas counter_stack only stores an entry once
        # you've gosubbed, but nothing for the current method.
        label, stack_size = args[0], args[1] - 1
        while @counter_stack.size > stack_size
          @counter_stack.pop
        end
        @counter = @label_to_counter[label] or raise "Can't find label #{label}"
      when 'GOSUB'
        label = args[0]
        @counter_stack.push @counter
        @counter = @label_to_counter[label] or raise "Can't find label #{label}"
      when 'RETURN'
        @counter = @counter_stack.pop
    end
  end

  def terminate_early
    @is_done = true       # so it's not possible to continue
    @num_steps_queued = 0 # so buttons aren't glowing
  end

  def stop_early
    @num_steps_queued = 0
  end

  private

  def label_to_counter bytecodes
    hash = {}
    bytecodes.each_with_index do |bytecode, counter|
      if bytecode[0] == :label
        label_name = bytecode[1]
        hash[label_name] = counter
      end
    end
    hash
  end
end
