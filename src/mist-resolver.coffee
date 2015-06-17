
#
#     _|      _|  _|              _|
#     _|_|  _|_|        _|_|_|  _|_|_|_|
#     _|  _|  _|  _|  _|_|        _|
#     _|      _|  _|      _|_|    _|
#     _|      _|  _|  _|_|_|        _|_|
#
#             MIST BUILD SYSTEM
# Copyright (c) 2015 On Demand Solutions, inc.

# This class resolves files given their base paths and mounts.
# This is the second step in fully rendering a Mist project.

# Implementations can take the result of this class and compile/render it
# any way they wish.

# The methodology for the resolver:
# 1) Generate templates for (order) dependencies and (aux) outputs
# 2) Generate a separate target for each globbed/grouped input
# 3) Run each resulting input through the previously generated templates
# 4) Run generated outputs as inputs for each rule relying on target group
# 4) Compile down non-foreach rules
# 5) Pass off to renderer

path = require 'path'
Globber = require './globber'
Hasher = require './hasher'

module.exports = class MistResolver
  constructor: (@rootDir, @rootMist)->
    @groupRefs = {}

    @setupTargets()
    @generateTemplates()
    @generateTargets()

  ###
  # Creates a targets object for each rule
  ###
  setupTargets: ->
    for rule in @rootMist.rules
      rule.targets = {}

  emitGroupOutput: (group, output)->
    (@groupRefs[group] = @groupRefs[group] || []).push output

  ###
  # Generates templates for dependencies and outputs
  ###
  generateTemplates: ->
    mktm = (i)=> @makeTemplate i

    for rule in @rootMist.rules
      rule.templates =
        dependencies: rule.src.dependencies.map mktm
        orderDependencies: rule.src.orderDependencies.map mktm
        outputs: rule.src.outputs.map mktm
        auxOutputs: rule.src.auxOutputs.map mktm

  ###
  # Transforms a source input into a template function
  #
  # input:
  #   The input pair generated from the parser
  # rule:
  #   The rule for this input
  ###
  makeTemplate: (input, rule)->
    switch input.type
      when 'glob' then (path, group)=>
        [] if group?
        path = MistResolver.delimitPath path, input.value
        Globber.performGlob path, @rootDir
      when 'group'
        @groupRefs[input.value] = @groupRefs[input.value] || []
      when 'simple' then (path, group)->
        [] if group?
        MistResolver.delimitPath path, input.value
      else
        throw "unknown template type: #{input.type}"

  generateTargets: ->
    groupSubs = {}
    for rule in @rootMist.rules
      for input in rule.src.inputs
        if input.type is 'group'
          (groupSubs[input.value] = groupSubs[input.value] || []).push rule

    for rule in @rootMist.rules
      for input in rule.src.inputs
        switch input.type
          when 'glob'
            results = Globber.performGlob input.value, @rootDir
            for result in results
              @processInput rule, result, null, groupSubs
          when 'group' then break
          else
            throw "unknown input type: #{input.type}"

  processInput: (rule, input, group, groupSubs = {})->
    return if input of rule.targets

    processor = (fn)->
      if fn instanceof Function
        fn input, group
      else
        fn

    rule.targets[input] =
      dependencies: rule.templates.dependencies.map processor
      orderDependencies: rule.templates.orderDependencies.map processor
      outputs: rule.templates.outputs.map processor
      auxOutputs: rule.templates.auxOutputs.map processor

    for k, a of rule.targets[input]
      rule.targets[input][k] = a.flatten()

    for group in rule.src.groups
      for output in rule.targets[input].outputs
        (@groupRefs[group] = @groupRefs[group] || []).push output
        if group of groupSubs
          for rule in groupSubs[group]
            @processInput rule, output, group, groupSubs

###
# Make sure to always include `$1` in the replacement
###
MistResolver.delimiterPattern = /((?!\%).)?%([fbB])/g

###
# Returns whether or not a string has filename delimiters present
#
# str:
#   The string to check
###
MistResolver.hasDelimiters = (str)->
  !!(str.match MistResolver.delimiterPattern)

###
# Delimits a template given a pathname
#
# Memoized!
#
# pathname:
#   The pathname to use when expanding the templates
# template:
#   A delimited template
###
MistResolver.delimitPath = (pathname, template)->
  dict = {}
  if pathname of @
    dict = @[pathname]
  else
    dict['f'] = pathname
    dict['b'] = path.basename pathname
    dict['B'] = dict['b'].replace /\..+$/, ''

  template.replace MistResolver.delimiterPattern, (m, p, c)->
    if c of dict then p + dict[c]
    else throw "unknown file delimiter: #{c}"

MistResolver.delimitPath = MistResolver.delimitPath.bind {}
