
local kollos_external = require "kollos"
local _khil = kollos_external._khil

g = _khil.grammar()
top = g:symbol_new()
a = g:symbol_new()
start_rule = g:rule_new(top, a)
g:start_symbol_set(top)
g:precompute()
print(start_rule)
g = nil