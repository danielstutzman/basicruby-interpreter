require 'opal'
require_relative '../lib/ast_to_bytecode_compiler'

def compile ruby_code
  parser = Opal::Parser.new
  sexp = parser.parse ruby_code
  compiler = AstToBytecodeCompiler.new
  compiler.compile_program 'test', sexp
end

describe AstToBytecodeCompiler, '#compile' do
  it 'compiles blank' do
    compile('').should == [[:result_nil]]
  end
  it 'compiles 3' do
    compile('3').should == [[:position, "test", 1, 0], [:token, 1, 0], [:result, 3]]
  end
  it 'compiles puts 3' do
    compile('puts 3').should == [
      [:position, "test", 1, 0], [:start_call], [:top], [:arg],
      [:token, 1, 0], [:result, 'puts'], [:make_symbol], [:arg],
      [:result_nil], [:arg],
      [:token, 1, 5], [:result, 3], [:arg],
      [:pre_call], [:call],
    ]
  end
  it 'compiles 3; 4' do
    compile('3; 4').should == [
      [:position, "test", 1, 0], [:token, 1, 0], [:result, 3], [:discard],
      [:position, "test", 1, 3], [:token, 1, 3], [:result, 4],
    ]
  end
  it 'compiles (3)' do
    compile('(3)').should == [[:position, "test", 1, 0], [:token, 1, 1], [:result, 3]]
  end
  it 'compiles x = 3' do
    compile('x = 3').should == [
      [:position, "test", 1, 0],
      [:token, 1, 0], [:start_vars, 'x'],
      [:token, 1, 4], [:result, 3],
      [:to_var, 'x'],
    ]
  end
  it 'compiles x = 3; x' do
    compile('x = 3; x').should == [
      [:position, "test", 1, 0], [:token, 1, 0], [:start_vars, 'x'],
      [:token, 1, 4], [:result, 3], [:to_var, 'x'], [:discard],
      [:position, "test", 1, 7], [:token, 1, 7], [:from_var, 'x'],
    ]
  end
  it 'compiles x = if true then 3 end' do
    compile('x = if true then 3 end').should == [
      [:position, "test", 1, 0], [:token, 1, 0], [:start_vars, 'x'],
      [:token, 1, 7], [:result, true],
      [:goto_if_not, "else_test_1_4"],
      [:position, "test", 1, 17],
      [:token, 1, 17], [:result, 3],
      [:goto, "endif_test_1_4"],
      [:label, "else_test_1_4"],
      [:result_nil],
      [:label, "endif_test_1_4"],
      [:to_var, 'x'],
    ]
  end
if false
  it 'compiles "1#{2}3"' do
    compile('"1#{2}3"').should == [
      [:position, "test", 1, 1],
      [:start_call], [:result, "1"], [:arg],
      [:result, '<<'], [:make_symbol], [:arg],
      [:token, 1, 4], [:result, 2], [:arg],
      [:token, 1, 6], [:result, "3"], [:arg],
      [:pre_call], [:call],
    ]
  end
end
  it 'compiles puts ""' do
    compile('puts ""').should == [
      [:position, "test", 1, 0], [:start_call], [:top], [:arg],
      [:token, 1, 0], [:result, 'puts'], [:make_symbol], [:arg],
      [:result_nil], [:arg],
      [:result, ""], [:arg], [:pre_call], [:call]
    ]
  end

  it 'compiles lambda { 4 }' do
    compile('lambda { 4 }').should == [
      [:position, "test", 1, 0], [:start_call], [:top], [:arg],
      [:token, 1, 0], [:result, 'lambda'], [:make_symbol], [:arg],
      [:goto, "after_return_test_1_9"],
      [:label, "start_test_1_9"],
      [:args, 0, 0], [:to_vars, -1, -1], [:discard],
      [:position, "test", 1, 9], [:token, 1, 9], [:result, 4], [:return],
      [:label, "after_return_test_1_9"], [:make_proc, "start_test_1_9"], [:arg],
      [:pre_call], [:call]
    ]
  end

  it 'compiles x,y=3,4' do
    compile('x,y=3,4').should == [
      [:position, "test", 1, 0], [:token, 1, 0], [:start_vars, 'x'],
      [:token, 1, 2], [:start_vars, 'y'],
      [:start_call], [:result_array], [:arg], [:result, 'push'], [:make_symbol],
      [:arg], [:result_nil],
      [:arg], [:token, 1, 4], [:result, 3],
      [:arg], [:token, 1, 6], [:result, 4],
      [:arg], [:pre_call], [:call],
      [:to_vars, -1, -1, 'x', 'y']
    ]
  end

  it 'compiles lambda{|x=1|}' do
    compile('lambda{|x=1|}').should == [
      [:position, "test", 1, 0], [:start_call],
      [:top], [:arg],
      [:token, 1, 0], [:result, 'lambda'], [:make_symbol], [:arg],
      [:goto, "after_return_test_1"], [:label, "start_test_2"],
      [:args, 0, 1, 'x'], [:to_vars, -1, -1, 'x'],
      [:discard],
      [:goto_param_defaults,
        "param_defaults_test_3_0", "param_defaults_test_4_1"],
        [:label, "param_defaults_test_3_0"],
          [:token, 1, 8], [:start_vars, 'x'], [:token, 1, 10],
          [:result, 1], [:to_var, 'x'], [:discard],
        [:label, "param_defaults_test_4_1"],
      [:result_nil], [:return],
      [:label, "after_return_test_1"],
      [:make_proc, "start_test_2"],
      [:arg], [:pre_call], [:call]
    ]
  end

  it 'compiles def f; 3; end' do
    compile('def f; 3; end').should == [
      [:position, "test", 1, 0], [:token, 1, 0],
      [:goto, "after_return_test_1_0"],
      [:label, "start_test_1_0"],
      [:args, 0, 0], [:to_vars, -1, -1], [:discard],
      [:position, "test", 1, 7], [:token, 1, 7], [:result, 3],
      [:return], [:label, "after_return_test_1_0"],
      [:start_call], [:top], [:arg],
      [:result, 'define_method'], [:make_symbol], [:arg],
      [:make_proc, "start_test_1_0"], [:arg],
      [:result, 'f'], [:make_symbol], [:arg],
      [:pre_call], [:call]
    ]
  end

  it 'compiles lambda{|&b|}' do
    compile('lambda{|&b|}').should == [
      [:position, "test", 1, 0], [:start_call], [:top], [:arg],
      [:token, 1, 0], [:result, 'lambda'], [:make_symbol], [:arg],
      [:goto, "after_return_test_1"], [:label, "start_test_2"],
      [:args, 0, 0, 'b'], [:to_vars, -1, 0, 'b'], [:discard],
      [:result_nil], [:return],
      [:label, "after_return_test_1"], [:make_proc, "start_test_2"],
      [:arg], [:pre_call], [:call]
    ]
  end

  # nil at the beginning to avoid nil source
  it 'compiles while false; 3; end' do
    compile('while false; 3; end').should == [
      [:position, "test", 1, 0], [:token, 1, 0],
      [:label, "start_test_1_6"],
      [:token, 1, 6], [:result, false], [:goto_if_not, "end_test_1_6"],
      [:token, 1, 13], [:result, 3], [:discard],
      [:goto, "start_test_1_6"], [:label, "end_test_1_6"], [:result_nil]
    ]
  end

  it 'compiles begin; 3; rescue Exception => e; end' do
    compile('begin; 3; rescue Exception => e; end').should == [
      [:position, "test", 1, 0], [:push_rescue, "rescue_test_1"],
      [:token, 1, 7], [:result, 3], [:pop_rescue, "rescue_test_1"],
      [:goto, "end_rescue_test_2"], [:label, "rescue_test_1"], [:discard],
      [:start_call], [:token, 1, 17], [:const, 'Exception'], [:arg],
        [:result, '==='], [:make_symbol], [:arg], [:result_nil], [:arg],
        [:from_gvar, '$!'], [:arg], [:pre_call], [:call],
      [:goto_if_not, "endif_test_3"],
      [:token, 1, 30], [:start_vars, 'e'], [:from_gvar, '$!'], [:to_var, 'e'],
      [:discard], [:result_nil], [:goto, "end_rescue_test_2"],
      [:label, "endif_test_3"],
      [:start_call], [:top], [:arg], [:result, 'raise'], [:make_symbol], [:arg],
        [:result_nil], [:arg], [:pre_call], [:call],
        [:label, "end_rescue_test_2"], [:clear_dollar_bang]
    ]
  end

  it 'compiles $a' do
    compile('$a').should == [
      [:position, "test", 1, 0], [:token, 1, 0], [:from_gvar, '$a']
    ]
  end
  it 'compiles $a = 1' do
    compile('$a = 1').should == [
      [:position, "test", 1, 0], [:token, 1, 0], [:token, 1, 5],
        [:result, 1], [:to_gvar, '$a']
    ]
  end
  it 'compiles :a' do
    compile(':a').should == [
      [:position, "test", 1, 1], [:token, 1, 1], [:result, 'a'], [:make_symbol]
    ]
  end
end
