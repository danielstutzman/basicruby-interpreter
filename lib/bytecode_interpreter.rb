UNNAMED_BLOCK = :__unnamed_block

if RUBY_PLATFORM == 'opal'
  # gets is not defined for opal, so define it
  def gets
  end

  # redefine puts to handle trailing newlines like MRI does
  def puts *args
    if args.size > 0
      $stdout.write args.map { |arg|
        arg_to_s = "#{arg}"
        arg_to_s + (arg_to_s.end_with?("\n") ? "" : "\n")
      }.join
    else
      $stdout.write "\n"
    end
  end

  def p *args
    args.each do |arg|
      $stdout.write arg.inspect + "\n"
    end
    case args.size
      when 0 then nil
      when 1 then args[0]
      else args
    end
  end
end

$console_texts = []
$is_capturing_output = false
class <<$stdout
  alias :old_write :write
  def write *args
    if $is_capturing_output
      $console_texts = $console_texts.clone +
        args.map { |arg| [:stdout, "#{arg}"] }
    else
      old_write *args
    end
  end
end
class <<$stderr
  alias :old_write :write
  def write *args
    if $is_capturing_output
      $console_texts = $console_texts.clone +
        args.map { |arg| [:stderr, "#{arg}"] }
    else
      old_write *args
    end
  end
end

class String
  def append(*args)
    self + args.map { |arg| "#{arg}" }.join
  end
end

class ProgramTerminated < RuntimeError
  attr_reader :cause
  def initialize(cause)
    @cause = cause
  end
end

class BytecodeInterpreter
  def initialize
    @partial_calls = []
    @num_partial_call_executing = nil
    @result = [] # a stack with 0 or 1 items in it
    @vars_stack = [{ __method_name: [false, "in '<main>'"] }]
    @main = (RUBY_PLATFORM == 'opal') ?
      `Opal.top` : TOPLEVEL_BINDING.eval('self')
    @accepting_input = false
    @accepted_input = nil
    @rescue_labels = []
      # list of tuples:
        # [0] label
        # [1] stack_size1 is with counting pop_next_one_too_on_return
        # [2] stack_size2 is when you don't count pop_next_one_too_on_return
        # [3] pc_size means partial_calls
        # [4] pending_var_names: so pending vars from start_vars get reset
    # path, method, line, col, pop_next_one_too_on_return
    @method_stack = [['Runtime', '<main>', nil, nil, false]]
    @methods_to_restore = {}
    $console_texts = []
    begin raise ''; rescue; end # set $! to RuntimeError.new('')
  end

  def undefine_methods!
    @methods_to_restore.reverse_each do |pair, method|
      receiver, method_name = pair
      if method
        receiver.singleton_class.send :define_method, method.name, &method
      else
        receiver.singleton_class.send :remove_method, method_name
      end
    end
  end

  def visible_state
    used_object_ids = [] # show closure variables only once
    {
      partial_calls: @partial_calls.map { |call| call.clone },
      vars_stack: @vars_stack.map do |vars|
        vars.reject do |name, tuple|
          if used_object_ids.include? tuple.object_id
            true
          else
            used_object_ids.push tuple.object_id
            false
          end
        end
      end,
      output: $console_texts,
      num_partial_call_executing: @num_partial_call_executing,
      accepting_input: @accepting_input,
      result: @result,
    }
  end

  def is_accepting_input?
    @accepting_input
  end

  def interpret bytecode #, speed, stdin
    case bytecode[0]
      when :position
        @method_stack.last[0] = bytecode[1] # path
        @method_stack.last[2] = bytecode[2] # line
        @method_stack.last[3] = bytecode[3] # col
        nil
      when :token
        @method_stack.last[2] = bytecode[1] # line
        @method_stack.last[3] = bytecode[2] # col
        nil
      when :result
        result_is bytecode[1]
        nil
      when :result_nil
        result_is nil
        nil
      when :result_array
        result_is []
        nil
      when :discard
        pop_result
        nil
      when :start_call
        @partial_calls.push []
        nil
      when :top
        result_is @main
        nil
      when :arg
        result = pop_result
        @partial_calls.last.push result
        nil
      when :make_proc
        result = Proc.new { |*args| ['RedirectMethod', bytecode[1]] }
        result.instance_variable_set '@env',
          @vars_stack.last.reject { |name, value| name == :__method_name }
        result.instance_variable_set '@defined_in', @method_stack.last
        result.instance_variable_set '@is_yield', false
        result_is result
        nil
      when :pre_call
        @num_partial_call_executing = @partial_calls.size - 1
        if @partial_calls.last == [@main, :gets, nil]
          @accepting_input = true
        end
        nil
      when :call
        @num_partial_call_executing = nil
        call = @partial_calls.last
        if @accepted_input != nil
          result_is @accepted_input
          @accepted_input = nil
          @partial_calls.pop
          nil
        else
          result = do_call *call
          if Array === result && result[0] == 'RedirectMethod'
            ['GOSUB', result[1]]
            # @method_stack.pop will be called by will_return
          elsif Array === result && result[0] == 'RESCUE'
            result_is nil
            @partial_calls.pop
            result
            # @method_stack.pop will be called by will_return
          else
            result_is result
            @partial_calls.pop
            nil
          end
        end
      when :return
        @partial_calls.pop
        @vars_stack.pop
        _, _, _, _, pop_next_method_too = @method_stack.pop
        if pop_next_method_too
          @vars_stack.pop
          @method_stack.pop
        end
        ['RETURN']
      when :start_vars
        _, *var_names = bytecode
        var_names.map! { |var_name| var_name.intern }
        var_names.each do |var_name|
          if @vars_stack.last.has_key? var_name
            @vars_stack.last[var_name][0] = true
          else
            @vars_stack.last[var_name] = [true]
          end
        end
        nil
      when :to_var
        var_name = bytecode[1].intern
        value = pop_result
        # store vars in arrays, so closures can modify their values
        # also array[0] stores whether array is awaiting a value or not
        @vars_stack.last[var_name][0] = false
        @vars_stack.last[var_name][1] = value
        result_is value
        nil
      when :to_vars
        _, splat_num, block_num, *var_names = bytecode
        var_names.map! { |var_name| var_name.intern }
        array = pop_result
        old_array = array.clone

        var_names.each_with_index do |var_name, i|
          if i == splat_num
            value = array
          elsif i == block_num
            value = @vars_stack.last[UNNAMED_BLOCK][1]
          else
            value = array.shift
          end
          # store vars in arrays, so closures can modify their values
          # also array[0] stores whether array is awaiting a value or not
          @vars_stack.last[var_name][0] = false
          @vars_stack.last[var_name][1] = value
        end
        if @vars_stack.last[UNNAMED_BLOCK]
          # clone the block so we can tell the difference between yield
          # (translated to __unnamed_block.call) vs. b.call (assuming a block
          # param that's named &b)
          old = @vars_stack.last[UNNAMED_BLOCK][1]
          new = Proc.new { |*args| old.call *args }
          new.instance_variable_set '@env', old.instance_variable_get('@env')
          new.instance_variable_set '@defined_in',
            old.instance_variable_get('@defined_in')
          new.instance_variable_set '@is_yield', true
          @vars_stack.last[UNNAMED_BLOCK][1] = new
        end
        result_is old_array
        nil
      when :from_var
        var_name = bytecode[1].intern
        if @vars_stack.last.has_key? var_name
          out = @vars_stack.last[var_name][1] # in array so closures can modify
          result_is out
        else
          raise "Looking up unset variable #{var_name}"
        end
        nil
      when :make_symbol
        result = pop_result.intern
        `result.is_symbol = true;` if RUBY_PLATFORM == 'opal'
        result_is result
        nil
      when :goto
        ['GOTO', bytecode[1]]
      when :goto_if_not
        result = pop_result
        if !result
          ['GOTO', bytecode[1]]
        else
          nil
        end
      when :args
        _, min_num_args, max_num_args, *var_names = bytecode
        var_names.map! { |var_name| var_name.intern }

        # Copy args from partial_calls to result
        receiver, method_name, block_arg, *args = @partial_calls.last
        result_is args

        # Complain if number of args is incorrect.
        # See http://www.ruby-doc.org/core-2.0.0/Proc.html for definition
        # of "tricks" -- mostly it means there's more flexibility
        # with the number of arguments allowed.
        tricks = (Proc === receiver && method_name == :call &&
                  receiver.lambda? == false)
        if tricks
          if args.size == 1 && Array === args[0]
            pop_result
            result_is args[0]
          end
        elsif (min_num_args && args.size < min_num_args) ||
                (max_num_args && args.size > max_num_args)
          num_expected =
            if max_num_args.nil? then "#{min_num_args}+"
            elsif min_num_args == max_num_args then min_num_args
            else "#{min_num_args}..#{max_num_args}"
            end
          message =
            "wrong number of arguments (#{args.size} for #{num_expected})"
          raise_exception { raise ArgumentError.new(message) }
        end

        # If this call is from proc.call, copy env vars over
        if Proc === @partial_calls.last[0]
          env = @partial_calls.last[0].instance_variable_get '@env'
          env.keys.each do |var_name|
            if !var_names.include?(var_name)
              @vars_stack.last[var_name] = env[var_name]
            end
          end
        end

        # Mark all non-env vars as pending (until :to_vars runs)
        var_names.each do |var_name|
          unless @vars_stack.last.has_key? var_name
            @vars_stack.last[var_name] = [true]
          end
        end

        # Always assign block_arg to __unnamed_block
        @vars_stack.last[UNNAMED_BLOCK] = [false, block_arg]

        nil
      when :goto_param_defaults
        num_args = @partial_calls.last.size - 3
        if 1 + num_args >= bytecode.size
          label = bytecode.last
        else
          label = bytecode[1 + (num_args)]
        end
        ['GOTO', label]
      when :push_rescue
        # save the stack size so we can easily remove any additional methods
        stack_size1 = @method_stack.size
        stack_size2 = @method_stack.count { |m| !m[4] }
        pending_var_names = @vars_stack.last.select { |var_name, tuple|
          tuple[0] }.values.map { |tuple| tuple[1] }
        @rescue_labels.push [bytecode[1], stack_size1, stack_size2,
          @partial_calls.size, pending_var_names]
        nil
      when :pop_rescue
        label, *_ = @rescue_labels.pop
        if label != bytecode[1]
          raise "Expected to pop #{bytecode[1]} but was #{label}"
        end
        nil
      when :to_gvar
        var_name = bytecode[1].intern
        value = pop_result
        eval "#{var_name} = value"
        result_is value
        nil
      when :from_gvar
        var_name = bytecode[1].intern
        if var_name.to_s == '$!'
          out = $! || $bang
        else
          out = eval var_name.to_s
        end
        result_is out
        nil
      when :const
        result_is Module.const_get(bytecode[1].intern)
        nil
      when :clear_dollar_bang
        # we extend $! so it's accesible from user code's rescue blocks,
        # even though we rescued the exception in our Opal code.
        # but don't extend $! forever; it should be nil after the user code's
        # rescue blocks end.
        $bang = nil
        nil
      when :done
        undefine_methods!
        nil
    end
  end

  def set_input text
    @accepted_input = text
    @accepting_input = false
    if false # don't automatically show inputted text; can be confused with output
      $console_texts = $console_texts.clone + [[:stdin, text]]
    end
  end

  def get_stdout
    stdout_pairs = $console_texts.select { |pair| pair[0] == :stdout }
    stdout_pairs.map { |pair| pair[1] }.join
  end

  def get_stderr
    stderr_pairs = $console_texts.select { |pair| pair[0] == :stderr }
    stderr_pairs.map { |pair| pair[1] }.join
  end

  def get_stdout_and_stderr
    $console_texts.select { |pair| pair[0] == :stdout || pair[0] == :stderr }
  end

  private

  def result_is new_result
    # use boxed JavaScript objects not primitives, so we can look up their
    # object_id, at least for strings. Maybe override number and bool's
    # object_id to be constant, like MRI's, later.
    if RUBY_PLATFORM == 'opal'
      `if (typeof(new_result) === 'number') {
        new_result = new Number(new_result);
      } else if (typeof(new_result) === 'string') {
        new_result = new String(new_result);
      }`
    end
    @result.push new_result
    raise "Result stack has too many items: #{@result}" if @result.size > 1
  end

  # since :args bytecode looks at partial_calls to determine what the
  # args were, it's not enough just to call the right method; we have
  # to setup partial_calls with arguments that the runtime expects.
  def simulate_call_to receiver, new_method_name, *args, &proc_
    entry = @method_stack.pop
    @method_stack.push [entry[0], new_method_name, nil, nil, false]
    @partial_calls.pop
    @partial_calls.push [receiver, new_method_name, proc_, *args]
    receiver.public_send new_method_name, *args
  end

  def do_call receiver, method_name, proc_, *args
    raise "Expected symbol for method_name" if !(Symbol === method_name)
    path, _, line_num = @method_stack.last
    @method_stack.push [path, method_name, line_num, nil, false]
    @vars_stack.push __method_name: [false, "in '#{method_name}'"]
    begin
      if method_name == :define_method
        begin
          old_method = receiver.method(args[0])
        rescue NameError
          old_method = nil
        end
        key = [receiver, args[0]]
        unless @methods_to_restore.has_key? key
          @methods_to_restore[key] = old_method
        end
      end

      result = \
      if receiver.respond_to?(method_name) && proc_ && %w[
        collect each each_index map reject select].include?(method_name.to_s)
        new_method_name = case method_name
          when :collect    then :__map # collect is aliased to map
          when :each       then :__each
          when :each_index then :__each_index
          when :map        then :__map
          when :reject     then :__reject
          when :select     then :__select
        end
        simulate_call_to @main, new_method_name, @partial_calls.last[0], &proc_

      elsif Array === receiver && proc_ &&
          %w[keep_if map! select!].include?(method_name.to_s)
        new_method_name = case method_name
          when :keep_if    then :__array_keep_if
          when :map!       then :__array_map!
          when :select!    then :__array_select!
        end
        simulate_call_to @main, new_method_name, @partial_calls.last[0], &proc_

      elsif method_name == :define_method
        receiver.singleton_class.send :define_method, *args, &proc_
        result = nil

      elsif method_name == :send
        new_method_name = args.shift
        result = simulate_call_to receiver, new_method_name, *args, &proc_

      elsif Proc === receiver && method_name == :call
        is_yield = receiver.instance_variable_get('@is_yield')
        if is_yield
          # discard the .call stack entry, because the user didn't write that
          @method_stack.pop
          @vars_stack.pop
        end
        path, method = receiver.instance_variable_get('@defined_in')
        @method_stack.push [path, "block in #{method}", nil, nil, !is_yield]
        @vars_stack.push __method_name: (method == '<main>') ?
          [false, "in block"] : [false, "in block in '#{method}'"]
        result = receiver.public_send method_name, *args, &proc_

      elsif Fixnum === receiver && method_name == :times
        simulate_call_to @main, :__fixnum_times, @partial_calls.last[0], &proc_

      elsif receiver == @main && method_name == :lambda
        # Procs generated by lambda should have proc.lambda? return true,
        # so re-create it.  Otherwise calling lambda will preserve
        # proc.lambda? as false.
        new = lambda { |*args| proc_.call *args }
        new.instance_variable_set '@env', proc_.instance_variable_get('@env')
        new.instance_variable_set '@defined_in',
          proc_.instance_variable_get('@defined_in')
        new.instance_variable_set '@is_yield',
          proc_.instance_variable_get('@is_yield')
        result = receiver.send method_name, *args, &new

      elsif receiver == @main
        begin
          $is_capturing_output = true
          result = @main.send method_name, *args, &proc_
          $is_capturing_output = false
          result
        rescue NoMethodError => e
          if args.size == 0 &&
             e.message == "undefined method `#{method_name}' for main"
            raise NameError.new "undefined local variable or method " +
              "`#{method_name}' for main:Object"
          else
            raise e
          end
        end

      else
        $is_capturing_output = true
        result = receiver.public_send method_name, *args, &proc_
        $is_capturing_output = false
        result
      end

      if Array === result && result[0] == 'RedirectMethod'
        # don't pop
      else
        @method_stack.pop
        @vars_stack.pop
      end
      result
    rescue Exception => e
      $is_capturing_output = false
      # don't call @method_stack.pop; exception handler will deal with it

      # It's necessary to write "return" here because of an Opal bug where
      # only the first rescue gets return like it should.
      return handle_exception(e)
    end
  end

  def raise_exception(&block)
    begin
      yield
    rescue => e
      handle_exception e
    end
  end

  def handle_exception e
    # take off the last entry (which is the backtrace call itself)
    # then sort with newer calls at top
    e.instance_variable_set :@backtrace,
      @method_stack[0...-1].reverse.map { |entry|
        sprintf("%s:%s:in `%s'", entry[0], entry[2], entry[1])
      }
    def e.backtrace
      @backtrace
    end

    if @rescue_labels.size > 0
      label, target_stack_size1, target_stack_size2, partial_calls_size,
        pending_var_names = @rescue_labels.pop
      while @method_stack.size > target_stack_size1
        @method_stack.pop
        @vars_stack.pop
      end
      while @partial_calls.size > partial_calls_size + 1
        @partial_calls.pop
      end
      @vars_stack.last.each do |var_name, tuple|
        if !pending_var_names.include?(var_name)
          tuple[0] = false # mark non-pending
        end
      end
      # don't do the last pop; something else will
      # $! gets set to nil after our rescue ends, but we'll want it defined
      # until the *user*'s rescue ends
      $bang = $!
      ['RESCUE', label, target_stack_size2]
    else
      text = "#{e.class}: #{e.message}\n" + e.backtrace.map { |entry|
        "  #{entry}" }.join("\n")
      $console_texts = $console_texts.clone + [[:stderr, text]]
      raise ProgramTerminated.new e
    end
  end

  def pop_result
    raise "Empty result stack" if @result == []
    @result.pop
  end

  def self.RUNTIME_PRELUDE
    <<EOF
def __each __input
  __enumerator = __input.each
  begin
    while true
      yield __enumerator.next
    end
  rescue StopIteration
  end
  __input
end
def __each_index __input
  __enumerator = __input.each_index
  begin
    while true
      yield __enumerator.next
    end
  rescue StopIteration
  end
  __input
end
def __array_keep_if array
  i = 0
  n = array.size
  while i < n
    if !(yield array[i])
      array.slice! i
      i -= 1
      n -= 1
    end
    i += 1
  end
  array
end
def __map __input
  __enumerator = __input.each
  __output = []
  begin
    while true
      __output.push yield __enumerator.next
    end
  rescue StopIteration
  end
  __output
end
def __array_map! array
  i = 0
  n = array.size
  while i < n
    array[i] = yield array[i]
    i += 1
  end
  array
end
def __reject __input
  __enumerator = __input.each
  __output = []
  begin
    while true
      __element = __enumerator.next
      __output.push(__element) unless yield(__element)
    end
  rescue StopIteration
  end
  __output
end
def __select __input
  __enumerator = __input.each
  __output = []
  begin
    while true
      __element = __enumerator.next
      __output.push(__element) if yield(__element)
    end
  rescue StopIteration
  end
  __output
end
def __array_select! array
  i = 0
  n = array.size
  changed = false
  while i < n
    if !(yield array[i])
      array.slice! i
      i -= 1
      n -= 1
      changed = true
    end
    i += 1
  end
  changed ? array : nil
end
def __fixnum_times num
  i = 0
  while i < num
    yield i
    i += 1
  end
  num
end
def assert_equal a, b
  if b != a
    raise "Expected \#{a.inspect} but got \#{b.inspect}"
  end
end
def __run_test test_name
  begin
    send test_name
    puts "\#{test_name} PASSED"
  rescue RuntimeError => e
    $stderr.write "\#{test_name} FAILED\\n"
    $stderr.write "\#{e}\\n"
    e.backtrace[0...-2].each do |line|
      $stderr.puts "  \#{line}\\n"
    end
  end
end
EOF
  end
end
