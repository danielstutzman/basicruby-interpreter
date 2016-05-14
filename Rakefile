def create_with_sh(command, path)
  begin
    sh "#{command} > #{path}"
  rescue
    sh "rm -f #{path}"
    raise
  end
end

task :clean do
  sh 'rm -rf build dist'
end

task :rspec do
  sh 'bundle exec rspec spec/*_spec.rb'
end

file 'build/ast_to_bytecode_compiler.js' =>
    'lib/ast_to_bytecode_compiler.rb' do |task|
  mkdir_p 'build'
  command = %W[
    bundle exec opal
      -c
      -I lib
      -- ast_to_bytecode_compiler
  ].join(' ')
  create_with_sh command, task.name
end

file 'build/bytecode_interpreter.js' =>
    'lib/bytecode_interpreter.rb' do |task|
  mkdir_p 'build'
  command = %W[
    bundle exec opal
      -c
      -I lib
      -- bytecode_interpreter
  ].join(' ')
  create_with_sh command, task.name
end

file 'build/lexer.js' => 'lib/lexer.rb' do |task|
  mkdir_p 'build'
  command = %W[
    bundle exec opal
      -c
      -I lib
      -- lexer
  ].join(' ')
  create_with_sh command, task.name
end

file 'build/bytecode_spool.js' => 'lib/bytecode_spool.rb' do |task|
  mkdir_p 'build'
  command = %W[
    bundle exec opal
      -c
      -I lib
      -- bytecode_spool
  ].join(' ')
  create_with_sh command, task.name
end

file 'dist/basicruby-interpreter.js' => %W[
  build/ast_to_bytecode_compiler.js
  build/bytecode_interpreter.js
  build/bytecode_spool.js
  build/lexer.js
] do |task|
  mkdir_p 'dist'
  create_with_sh "cat #{task.prerequisites.join(' ')}", task.name
end

task :default => %w[
  dist/basicruby-interpreter.js
]
