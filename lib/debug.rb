require 'readline'
require 'opal'
require 'pp'
require_relative './ast_to_bytecode_compiler'
require_relative './bytecode_interpreter'
require_relative './bytecode_spool'

path = ARGV[0] or raise "First argument: path to ruby source file"
ruby_code = File.read(path)

parser = Opal::Parser.new
compiler = AstToBytecodeCompiler.new
sexp1 = parser.parse BytecodeInterpreter.RUNTIME_PRELUDE
bytecodes1 = compiler.compile_program 'runtime', sexp1
bytecodes1.reject! { |bytecode| [:position, :token].include?(bytecode[0]) }
sexp2 = parser.parse ruby_code
bytecodes2 = compiler.compile_program 'user', sexp2
bytecodes = bytecodes1 + [[:discard]] + bytecodes2
spool = BytecodeSpool.new bytecodes
interpreter = BytecodeInterpreter.new

bytecodes.each_with_index do |bytecode, i|
  puts sprintf('%4d  %s', i, bytecode.join(' '))
end
puts

breakpoints = [ bytecodes1.size ] # start at user's code

while true
  spool.queue_run_until 'NEXT_BYTECODE'
  bytecode = spool.get_next_bytecode or break
  begin
    spool_command = interpreter.interpret bytecode
  rescue ProgramTerminated => e
    puts "At counter #{spool.counter}:"
    raise e.cause
  rescue
    puts "At counter #{spool.counter}:"
    raise
  end
  spool.do_command *spool_command if spool_command
  if breakpoints.include? spool.counter
    spool.stop_early
    break
  end
end

while true
  code_line = (bytecodes[spool.counter] || []).join(' ')
  puts sprintf('%4d  %s', spool.counter, code_line)
  line = Readline.readline("> ", true) or break
  case line.split(' ')[0]
    when 'run', 'r'
      spool.queue_run_until 'DONE'
    when 'next', 'n'
      spool.queue_run_until 'NEXT_BYTECODE'
    when 'info', 'i'
      pp interpreter.visible_state
    when 'break', 'b'
      breakpoints.push line.split(' ')[1].to_i
    when 'list', 'ls', 'l'
      min_counter = [spool.counter - 5, 0].max
      max_counter = [spool.counter + 5, bytecodes.size].min
      (min_counter...max_counter).each do |i|
        puts sprintf('%s %4d  %s',
          i == spool.counter ? '*' : ' ', i, bytecodes[i].join(' '))
      end
      puts
    else
      puts 'Unknown command'
  end

  while true
    bytecode = spool.get_next_bytecode or break
    begin
      spool_command = interpreter.interpret bytecode
    rescue ProgramTerminated => e
      puts "At counter #{spool.counter}:"
      raise e.cause
    rescue Exception => e
      puts "At counter #{spool.counter}:"
      raise
    end
    spool.do_command *spool_command if spool_command
    if breakpoints.include? spool.counter
      spool.stop_early
      break
    end
  end
end
