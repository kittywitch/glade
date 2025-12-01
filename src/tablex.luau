local tablex = {}

export type TableWildcard = { [any]: any }

function tablex.combine<T>(t1: {T}, t2: {T}): ()
  local len = #t1
  for i=1, #t2 do
    t1[len+i] = t2[i]
  end
end

function tablex.combine_kv<Tk, Tv>(t1: {[Tk]: Tv}, t2: {[Tk]: Tv}): ()
  for k, v in t2 do
    t1[k] = v
  end
end

function tablex.keys(t: TableWildcard): TableWildcard
  local keys = {}
  for key, _ in t do
    table.insert(keys, key)
  end
  return keys
end

function tablex.values(t: TableWildcard): TableWildcard
  local values = {}
  for _, value in t do
    table.insert(values, value)
  end
  return values
end

function tablex.strip_values(t: TableWildcard): TableWildcard
  local new_table = {}
  for key, val in t do
    if type(val) ~= "table" then
      table.insert(new_table, key)
    else
      new_table[key] = tablex.strip_values(val)
    end
  end
  return new_table
end

function tablex.get_fake_key(t: TableWildcard, path: TableWildcard): TableWildcard
  local context = t
  for _, subpath in tablex.get_n_minus(path, 1) do
    for _, v in t do
      if v.content == subpath then
        context = v.children
      end
    end
  end
  return context
  
end

function tablex.get_n(t: TableWildcard, n: number): TableWildcard
  local t2 = {}
  return table.move(t, 1, n, 1, t2)
end

function tablex.get_n_minus(t: TableWildcard, n: number): TableWildcard
  local len = #t
  return tablex.get_n(t, len-n)
end

function tablex.sort_bullshit(t: TableWildcard): TableWildcard
  local keys = tablex.keys(t)
  table.sort(keys)
  local new_table = {}
  for i=1,#keys do
    table.insert(new_table, t[keys[i]])
  end
  return new_table
end

return tablex
