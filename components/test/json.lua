--[[

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

[ MIT license: http://www.opensource.org/licenses/mit-license.php ]

--]]

--[[

The primary aim of this parser is to test Kollos as a platform for
arbitrary grammars. Speed is also an aim, but secondary.

In keeping with these priorities, JSON is treated as if there were no
existing code for it -- after all, if I wanted a fast JSON parser I could
just grab a very fast C language recursive descent parser from somewhere.
Everything is created "from scratch" using tools which generalize to
other parsers. For example, I'm sure there is code out there in both
Lua and C to crunch JSON strings, code which is both better and faster
than what is here, but I do not use it.

--]]

-- eventually merge this code into the kollos module
-- for now, we include it when we get various utility methods
-- local kollos_external = require "kollos"

local dumper = require "dumper"

local json_kir =
{
  -- tokens in l0 are at a lower level than
  -- "tokens" as defined in RFC 7159, section 2
  -- RFC 7159 does not separate semantics from syntax --
  -- if you assume either top-down parsing (as in recursive
  -- descent) or a dedicated lexer (as in yacc) there's no
  -- need to make the separation.
  l0 = {
    irule = {
      -- ws before and after <value>, see RFC 7159, section 2
      { lhs='ws_before', rhs={ 'ws' } },
      { lhs='ws_after', rhs={ 'ws' } },
      -- next rules are ws ::= ws_char*
      { lhs='ws', rhs={ 'ws_seq' } },
      { lhs='ws_seq', rhs={ 'ws_seq', 'ws_char' } },
      { lhs='ws_seq', rhs={ 'ws_char' } },
      { lhs='ws_seq', rhs={ } }, -- empty
      { lhs='begin_array', rhs = { 'ws', 'lsquare', 'ws' } },
      { lhs='begin_object', rhs = { 'ws', 'lcurly', 'ws' }},
      { lhs='end_array', rhs = { 'ws', 'rsquare', 'ws' }},
      { lhs='end_object', rhs = { 'ws', 'rcurly', 'ws' }},
      { lhs='name_separator', rhs = { 'ws', 'colon', 'ws' }},
      { lhs='value_separator', rhs = { 'ws', 'comma', 'ws' }},
      { lhs='false', rhs = { 'char_f', 'char_a', 'char_l', 'char_s', 'char_e' }},
      { lhs='true', rhs = { 'char_t', 'char_r', 'char_u', 'char_e' }},
      { lhs='null', rhs = { 'char_n', 'char_u', 'char_l', 'char_l' }},
      { lhs='minus', rhs = { 'char_minus' }},

      -- Lua number format seems to be compatible with JSON,
      -- so we treat a JSON number as a full token
      { lhs='number', rhs = { 'opt_minus', 'int', 'opt_frac', 'opt_exp' }},
      { lhs='opt_minus', rhs = { 'char_minus' } },
      { lhs='opt_minus', rhs = { } },
      { lhs='opt_exp', rhs = { 'exp' } },
      { lhs='opt_exp', rhs = { } },
      { lhs='exp', rhs = { 'e_or_E', 'opt_sign', 'digit_seq' } },
      { lhs='e_or_E', rhs = { 'char_e' } },
      { lhs='e_or_E', rhs = { 'char_E' } },
      { lhs='opt_sign', rhs = { } },
      { lhs='opt_sign', rhs = { 'char_minus' } },
      { lhs='opt_sign', rhs = { 'char_plus' } },
      { lhs='opt_frac', rhs = { } },
      { lhs='opt_frac', rhs = { 'frac' } },
      { lhs='frac', rhs = { 'dot', 'digit_seq' } },
      { lhs='int', rhs = { 'char_nonzero', 'digit_seq' } },
      { lhs='digit_seq', rhs = { 'digit_seq', 'char_digit' } },
      { lhs='digit_seq', rhs = { 'char_digit' } },

      -- we divide up the standards string token, because we
      -- need to do semantic processing on its pieces
      { lhs='quote', rhs = { 'char_escape', 'char_quote' } },
      { lhs='backslash', rhs = { 'char_escape', 'char_backslash' } },
      { lhs='slash', rhs = { 'char_escape', 'char_slash' } },
      { lhs='backspace', rhs = { 'char_escape', 'char_b' } },
      { lhs='formfeed', rhs = { 'char_escape', 'char_f' } },
      { lhs='linefeed', rhs = { 'char_escape', 'char_n' } },
      { lhs='carriage_return', rhs = { 'char_escape', 'char_r' } },
      { lhs='tab', rhs = { 'char_escape', 'char_t' } },
      { lhs='hex_char', rhs = { 'char_escape', 'char_u', 'hex_digit', 'hex_digit', 'hex_digit', 'hex_digit' } },
      { lhs='simple_string', rhs = { 'char_escape', 'unescaped_char_seq' } },
      { lhs='unescaped_char_seq', rhs = { 'unescaped_char_seq', 'unescaped_char' } },
      { lhs='unescaped_char_seq', rhs = { 'unescaped_char' } }
    },

    isym = {
      ['ws_before'] = { lexeme = true },
      ['ws_after'] = { lexeme = true },
      ['begin_array'] = { lexeme = true },
      ['begin_object'] = { lexeme = true },
      ['end_array'] = { lexeme = true },
      ['end_object'] = { lexeme = true },
      ['name_separator'] = { lexeme = true },
      ['value_separator'] = { lexeme = true },
      ['false'] = { lexeme = true },
      ['true'] = { lexeme = true },
      ['null'] = { lexeme = true },
      ['minus'] = { lexeme = true },
      ['number'] = { lexeme = true },
      ['quote'] = { lexeme = true },
      ['backslash'] = { lexeme = true },
      ['slash'] = { lexeme = true },
      ['backspace'] = { lexeme = true },
      ['formfeed'] = { lexeme = true },
      ['linefeed'] = { lexeme = true },
      ['carriage_return'] = { lexeme = true },
      ['tab'] = { lexeme = true },
      ['hex_char'] = { lexeme = true },
      ['simple_string'] = { lexeme = true },
      ['digit_seq'] = {},
      ['exp'] = {},
      ['frac'] = {},
      ['int'] = {},
      ['e_or_E'] = {},
      ['opt_exp'] = {},
      ['opt_frac'] = {},
      ['opt_minus'] = {},
      ['opt_sign'] = {},
      ['unescaped_char_seq'] = {},
      ['ws'] = {},
      ['ws_seq'] = {},
      ['char_slash'] = { charclass = "[\047]" },
      ['char_backslash'] = { charclass = "[\092]" },
      ['char_escape'] = { charclass = "[\092]" },
      ['unescaped_char'] = { charclass = "[ !\035-\091\093-\255]" },
      ['ws_char'] = { charclass = "[\009\010\013\032]" },
      ['lsquare'] = { charclass = "[\091]" },
      ['lcurly'] = { charclass = "[{]" },
      ['hex_digit'] = { charclass = "[%x]" },
      ['rsquare'] = { charclass = "[\093]" },
      ['rcurly'] = { charclass = "[}]" },
      ['colon'] = { charclass = "[:]" },
      ['comma'] = { charclass = "[,]" },
      ['dot'] = { charclass = "[.]" },
      ['char_quote'] = { charclass = '["]' },
      ['char_nonzero'] = { charclass = "[1-9]" },
      ['char_digit'] = { charclass = "[0-9]" },
      ['char_minus'] = { charclass = '[-]' },
      ['char_plus'] = { charclass = '[+]' },
      ['char_a'] = { charclass = "[a]" },
      ['char_b'] = { charclass = "[b]" },
      ['char_E'] = { charclass = "[E]" },
      ['char_e'] = { charclass = "[e]" },
      ['char_f'] = { charclass = "[f]" },
      ['char_l'] = { charclass = "[l]" },
      ['char_n'] = { charclass = "[n]" },
      ['char_r'] = { charclass = "[r]" },
      ['char_s'] = { charclass = "[s]" },
      ['char_t'] = { charclass = "[t]" },
      ['char_u'] = { charclass = "[u]" },
    }

  },
}

-- given a transition matrix, which is a
-- table of tables such that matrix[a][b]
-- is true if there is a transition from
-- a to b, change it into its closure
local function transition_closure(matrix)
    -- as an efficiency hack, we store the
    -- from, to duples as two entries, so
    -- that we don't have to create a table
    -- for each duple
    local work_list = {}
    for from,to in ipairs(matrix) do
        for from,transition in ipairs(columns) do
            if transition then
                table.insert(worklist, from )
                table.insert(worklist, to )
            end
        end
    end
    while true
         -- unstack in reverse order of the
         -- way they were stacked
         work_to = table.remove(work_list)
         work_from = table.remove(work_list)
         -- NOT FINISHED
    end
end

-- We leave the KIR as is, and work with
-- intermediate databases

local function do_grammar(grammar, properties)

  local g_is_structural = properties['structural']

  local lhs_by_rhs = {}
  local rhs_by_lhs = {}
  local lhs_rule_by_rhs = {}
  local rhs_rule_by_lhs = {}
  local sym_is_nullable = {}
  local sym_is_lexeme = {}
  local sym_is_productive = {}
  local sym_is_sizable = {}
  local sym_is_solid = {}

  for symbol,v in pairs(properties['isym']) do
    lhs_by_rhs[symbol] = {}
    rhs_by_lhs[symbol] = {}
    lhs_rule_by_rhs[symbol] = {}
    rhs_rule_by_lhs[symbol] = {}
  end

  -- Next we start the database of intermediate KLOL symbols
  for rule_ix,v in ipairs(properties['irule']) do
    local lhs = v['lhs']
    if (not lhs_by_rhs[lhs]) then
      error("Internal error: Symbol " .. lhs .. " is lhs of irule but not in isym")
    end
    table.insert(rhs_rule_by_lhs[lhs], rule_ix)
    local rhs = v['rhs']
    if (#rhs == 0) then
      sym_is_nullable[lhs] = true
      sym_is_productive[lhs] = true
    end
    for dot_ix,rhs_item in ipairs(rhs) do
      if (not lhs_by_rhs[rhs_item]) then
        error("Internal error: Symbol " .. rhs_item .. " is rhs of irule but not in isym")
      end
      table.insert(lhs_rule_by_rhs[rhs_item], rule_ix)
      lhs_by_rhs[rhs_item][lhs] = true
      rhs_by_lhs[lhs][rhs_item] = true
    end
  end
  local symbol_count = 0
  for symbol,v in pairs(properties['isym']) do
    symbol_count = symbol_count + 1
    if (not lhs_by_rhs[symbol] and not rhs_by_lhs[symbol]) then
      error("Internal error: Symbol " .. symbol .. " is in isym but not in irule")
    end
    if (v['charclass']) then
      if (#rhs_rule_by_lhs[symbol] > 0) then
        -- print(symbol, dumper.dumper( rhs_rule_by_lhs[symbol]))
        error("Internal error: Symbol " .. symbol .. " has charclass but is on LHS of irule")
      end
      sym_is_sizable[symbol] = true
      sym_is_solid[symbol] = true
      sym_is_productive[symbol] = true
    end
    if (v['lexeme']) then
      if (g_is_structural) then
        error('Internal error: Lexeme "' .. lexeme .. '" declared in structural grammar')
      end
      sym_is_lexeme[symbol] = true
      -- print( "Setting lexeme symbol ", symbol )
    end
    if (v['start']) then
      if (not g_is_structural) then
        error('Internal error: Start symbol "' .. symbol '" declared in lexical grammar')
      end
      start_symbol = symbol
    end
  end

  -- print( "Initial symbol count ", symbol_count )

  -- I expect to handle cycles eventually, so this logic must be
  -- cycle-safe.

  if (g_is_structural and not start_symbol) then
    if (not g_is_structural) then
      error('Internal error: No start symbol in structural grammar')
    end
  end

  -- Test for reachability from start symbol,
  -- or from a lexeme
  -- At this point an unreachable symbol is a fatal error
  do
    local reachable = {}
    local reachable_count = 0
    local work_list = {}
    if (g_is_structural) then
      reachable[start_symbol] = true
      reachable_count = reachable_count + 1
      -- print( "Setting reachable symbol ", start_symbol )
      table.insert(work_list, start_symbol)
    else
      for lexeme,v in pairs(sym_is_lexeme) do
        reachable[lexeme] = v
        reachable_count = reachable_count + 1
        -- print ("Setting reachable symbol ", lexeme )
        table.insert(work_list, lexeme)
      end
    end
    while true do
      work_symbol = table.remove(work_list)
      if (not work_symbol) then break end
      for next_symbol, v in pairs(rhs_by_lhs[work_symbol]) do
        if not reachable[next_symbol] then
          reachable[next_symbol] = true
          -- print ("Setting reachable symbol ", next_symbol )
          reachable_count = reachable_count + 1
          table.insert(work_list, next_symbol)
        end
      end
    end
    if (reachable_count ~= symbol_count) then
      for symbol,v in pairs(properties['isym']) do
        if (not reachable[symbol]) then
          print('Internal error: KIR isym "' .. symbol .. '" not reachable')
        end
      end
      error('Internal error: ' .. (symbol_count-reachable_count) .. ' KIR symbols not reachable')
    end
  end

  print (dumper.dumper(rhs_by_lhs))

end

for grammar,properties in pairs(json_kir) do
  do_grammar(grammar, properties)
end

-- vim: expandtab shiftwidth=4:
