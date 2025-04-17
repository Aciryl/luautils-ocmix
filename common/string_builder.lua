---------------------------------------
-- 文字列を継ぎ足して1つの文字列にする
---------------------------------------
--[[ 使い方
  初期化:
  local string_builder = require("string_builder")
  local sb = string_builder.new()
  
  文字列の挿入:
  sb:append(<文字列>) -- 改行なしで挿入
  sb:append_line(<文字列>) -- 文字列を挿入後に改行を挿入
  
  文字列に変換:
  sb:tostring()
  tostring(sb)
  print(sb) -- 内部的に tostring(sb) が呼ばれる
]]

-- メソッドリストの宣言
local string_builder_methods

-- 本体
local StringBuilder = {
  -- インスタンスを作成
  new = function()
    -- データを格納するテーブル
    local obj = { data = "" }
    
    -- メタテーブルを設定する
    setmetatable(obj, {
      -- obj に含まれていないキーでアクセスされた場合に func_table の中を代わりに見る
      __index = string_builder_methods,
      -- tostring(obj) とした時に表示するものを設定する
      __tostring = function(sb)
        return sb:tostring()
      end
    })
    
    -- データが入ったテーブル(オブジェクト)を返す
    return obj
  end,
}

-- StringBuilder の関数を保持するテーブル
string_builder_methods = {
  -- 文字列を追加(改行なし)
  append = function(self, text)
    self.data = self.data .. tostring(text)
    return self -- メソッドチェーンに対応
  end,
  
  -- 文字列を追加して改行
  append_line = function(self, text)
    self.data = self.data .. tostring(text) .. "\n"
    return self -- メソッドチェーンに対応
  end,
  
  tostring = function(self)
    return self.data
  end,
}

return StringBuilder

