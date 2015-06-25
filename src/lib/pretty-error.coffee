 #
 #     _|      _|  _|              _|
 #     _|_|  _|_|        _|_|_|  _|_|_|_|
 #     _|  _|  _|  _|  _|_|        _|
 #     _|      _|  _|      _|_|    _|
 #     _|      _|  _|  _|_|_|        _|_|
 #
 #             MIST BUILD SYSTEM
 # Copyright (c) 2015 On Demand Solutions, inc.

# for implementations using this:
#   note the distinction between cases of `filename` and `fileName`:
#   the former is for mistfile problems; the latter is generated automateically
#   by the Error object to indicate the origin in the program.
#
#   Do not set `fileName`, but rather `filename`.
#   I know it's confusing. Bite me.

chalk = require 'chalk'
fs = require 'fs'
path = require 'path'

col = [
  "\x1b[0G"
  "\x1b[3G"
  "\x1b[13G"
  "\x1b[26G"
]

paragraph = (lines...)-> lines.filter((a)->a?).join '\n'
line = (args...)->
  l = args.filter((a)->a?).join ''
  l if l and l.length

compileExpected = (expected)->
  first = yes
  results = for e in expected.filter((i)->i.type isnt 'other')
    l = [
      if first
        first = no
        "#{col[1]}expected#{col[2]}"
      else
        "#{col[1]}or#{col[2]}"
      chalk.cyan.bold(e.description),
      col[3]
      if e.type then " #{chalk.dim.grey(e.type)}"
      if e.value then " #{chalk.dim.grey(e.value)}"
    ].filter((a)->a?).join ''
    l if l and l.length
  results.join '\n'

compileFileMarker = (filename, line, column)->
  try
    compileSourceMarker fs.readFileSync(filename).toString(), line, column

compileSourceMarker = (src, line, column)->
  lines = src.split /\r?\n/g
  line = lines[line-1]
  return if not (line and line.length)

  result = ['\n', line]
  if column
    c = column - 2
    d = if c < 0
        c = Math.abs c
        'D'
      else
        'C'
    result.push "\x1b[#{c}#{d}#{chalk.red.bold('^')}"

  result.join "\n#{col[1]}"

betterStack = (stack)->
  lines = stack.split /\r?\n/g
  lines = lines.slice 1 # get rid of the error
  lines = lines.map (line)->
    line.match /^\s*at\s+((?:(?!\s+\().)+)\s+\(([^:)]+)(:\d+:\d+)?\)$/
  found = no
  lines = lines.filter (line)->
    if abs = path.isAbsolute line[2]
      found = yes
    abs || not found
  lines = lines.map (line)->
    "#{col[1]}in#{col[2]}#{line[1]} (#{line[2]}#{line[3]})"
  lines.join '\n'

module.exports = (e)->
  if e.constructor is String then e = message:e
  if e.line? and e.map?
    e.line = e.map[e.line]

  console.error paragraph null,
    line '\n',
      chalk.red.bold('ERROR: '),
      e.message || 'unexpected error'

    line null,
      if e.filename or e.line then "#{col[1]}at#{col[2]}"
      if e.filename or e.line then e.filename || '[unknown]'
      if e.line then ":#{e.line}"
      if e.line and e.column then ":#{e.column}"

    line null,
      # peg error
      if e.expected then compileExpected e.expected

    line null,
      # line/col resolution
      if e.source and e.line then compileSourceMarker e.source, e.line, e.column
      else if e.filename and e.line then compileFileMarker e.filename, e.line,
        e.column

    line null
      # stack
      if e.stack then chalk.dim.grey betterStack e.stack

  process.exit 10
