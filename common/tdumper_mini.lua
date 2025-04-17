--------------------------------------------
-- テーブルの中身を再帰的に表示する(簡易版)
--------------------------------------------

--[[ 使い方
  local tdumper_mini = require("tdumper_mini")
  tdumper_mini.dump(<表示したいテーブル>[, <テーブルの名前>])
  とすると、テーブルの中身が文字列として返されます
  
  戻り値の文字列の例:
  my_table = {
    123 = 123,
    "123" = 123,
    "str" = "123",
    "tbl_A" = {
      "func" = function: 00000257ebc971e0,
      "tbl_B" = {
        * 既に表示済み -> my_table.tbl_A
      },
      <tostring() = "1行目
  2行目
  3行目">
    },
  }
  数字と文字列は、"" がついているかどうかで区別できます
]]

-- テーブル t1 に テーブル t2 の要素を追加する
local table_concat_array = function(t1, t2)
  for i = 1, #t2 do table.insert(t1, t2[i]) end
end

-- 本体
local TDumperMini
TDumperMini = {-- テーブルを表示する際の、1階層ごとにつけるインデント
  INDENT_UNIT = "  ",
  
  -- テーブルの中身を再帰的に表示する(循環参照も OK)
  -- tbl:table > 中身を表示したいテーブル
  -- [tbl_name:string] > テーブル名(省略可)
  -- :string > 戻り値: テーブルの中身を表した文字列
  dump = function(tbl, tbl_name)
    local result = {}-- 出力を溜める配列
    
    -- tbl が table型では無かった時は、エラーメッセージを表示する
    if type(tbl) ~= "table" then
      table.insert(result, "関数: TDumperMini.dump() でエラーが発生しました")
      table.insert(result, "引数: tbl(" .. tostring(tbl_name) .. ") は table型が必要です (受け取った型: " .. type(tbl) .. ")")
      return table.concat(result, "\n")
    end
    
    -- トップレベルの表記
    if not tbl_name or tbl_name == "" then -- tbl_name が nil か空文字の時はテーブル名を "<top_table>" にする
      tbl_name = "<top_table>"
    end
    tbl_name = tostring(tbl_name) -- tbl_name が string でなくても安全なように
    
    -- 出力
    table.insert(result, tbl_name .. " = {")
    table_concat_array(result, TDumperMini._inner_dump(tbl, tbl_name, TDumperMini.INDENT_UNIT)) -- 実際にテーブルをダンプする処理(再帰関数)
    table.insert(result, "}") -- 最後にテーブルを閉じる
    
    return table.concat(result, "\n")
  end,
  
  -- 実際にテーブルをダンプする関数(再帰関数)
  _inner_dump = function(tbl, key_path, indent, visited)
    indent = indent or ""
    visited = visited or {}
    local result = {}
    
    -- 循環参照検出時はその先の検索を中止
    if visited[tbl] then
      table.insert(result, indent .. "* 既に表示済み -> " .. visited[tbl])
      return result
    end
    -- tbl をダンプ済みテーブルとしてマークする
    visited[tbl] = key_path
    
    -- テーブルに含まれる要素をチェックし、値の型によって動作を分ける
    for k, v in pairs(tbl) do
      local key_str
      -- キーが string の時は "" で囲む
      if type(k) == "string" then
        key_str = "\"" .. k .. "\""
      else
        key_str = tostring(k) -- キー名を安全に結合できるように string にする
      end
      local value_type = type(v)
      if value_type == "table" then
        -- 値がテーブルの時は、再帰的に子要素を検索
        table.insert(result, indent .. key_str .. " = {")
        table_concat_array(result, TDumperMini._inner_dump(v, key_path .. "." .. key_str, indent .. TDumperMini.INDENT_UNIT, visited)) -- 再帰的呼び出し
        table.insert(result, indent .. "},")
      elseif value_type == "string" then
        -- 値が string の時は "" で囲んで出力
        table.insert(result, indent .. key_str .. " = \"" .. v .. "\",")
      else
        -- 値がそれ以外の時は、そのまま string に変換して出力
        table.insert(result, indent .. key_str .. " = " .. tostring(v) .. ",")
      end
    end
    
    -- 最後に __tostring があるものは、それを追記する
    local mt = getmetatable(tbl)
    if mt and type(mt.__tostring) == "function" then -- メタテーブルに __tostring が設定されている場合
      -- 出力
      table.insert(result, indent .. "<tostring() = \"" .. tostring(tbl) .. "\">")
    end
    
    return result
  end,
}

return TDumperMini

