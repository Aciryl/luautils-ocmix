------------------------------------
-- テーブルの中身を再帰的に表示する
------------------------------------

-- Version = 1.0.2

--[[ 使い方 - 簡易版 -
  local table_dumper = require("table_dumper")
  table_dumper:dump(<表示したいテーブル>[, <テーブルの名前>])
  または
  table_dumper.new(<ロガー>):dump(引数は上と同じ)
  とすると、テーブルの中身が文字列として返されます
  
  print(table_dumper) とすると、もう少し詳しい説明が表示されます
  
  戻り値の文字列の例:
  my_table = {
    123 = 123,
    "123" = 123,
    "str" = "123",
    "tbl_A" = {
      "func" = function: 00000257ebc971e0,
      "multi_line" = "1行目
                      2行目
                      3行目",
      "tbl_B" = {
        * 既に表示済み(循環参照) -> my_table.tbl_A
      },
      "tbl_C" = {
      },
      <tostring() = "1行目
                     2行目
                     3行目">
    },
    "tbl_D" = {
      * 既に表示済み(共有参照) -> my_table.tbl_A.tbl_C
    },
  }
  数字と文字列は、"" がついているかどうかで区別できます
  
  insert_indent が false の場合は以下のようになります
  my_table2 = {
    "multi_line" = "1行目
  2行目
  3行目",
    <tostring() = "1行目
  2行目
  3行目">
  }
  文字列をコピーしたい時はこのオプションを使ってください
  
  ※ キー名に改行が含まれている場合は表示が崩れます
]]

-- table_dumper モジュールのバージョン
local VERSION = "1.0.2"

-- モジュールのインポート
local string_builder = require("string_builder") -- 文字列を継ぎ足して1つの文字列にする

-- デフォルトのロガーの宣言
local Logger
-- 関数の宣言
local is_array
local comparator

-- __tostring が定義されているかどうかを判定する
local has_tostring = function(value)
  local mt = getmetatable(value)
  return mt ~= nil and type(mt.__tostring) == "function"
end

-- テーブルを表示するメソッドが入った本体
local TableDumper
TableDumper = {
  -- table_dumper モジュールのバージョン
  VERSION = VERSION,
  
  -- テーブルを表示する際の、1階層ごとにつけるインデント
  INDENT_UNIT = "  ",
  
  -- 文字列を表示する時に、改行後にインデントを挿入するかどうか
  insert_indent = true,
  
  -- tostring() を表示する時に、改行後にインデントを挿入するかどうか。0 で insert_indent の値を使います
  insert_indent_tostring = 0,
  
  -- new() をしないでいきなり dump() を呼んだ時に使う
  -- TableDumper の定義の下で setmetatable() に使っています
  _default_obj = false, -- nil だとキーが存在しないことになって、setmetatable が StackOverflow してしまう
  
  -- ロガーを設定した dump() が入っているテーブル(オブジェクト)を返します
  -- [logger:Logger] > エラーなどを出力するロガー(省略可)
  --                   Logger は logger.error(msg:string) または logger.debug(msg:string) という形式でログ出力をするオブジェクトを想定しています
  --                   お使いのロガーと関数名などが合わない場合は "logger." で検索して書き換えてください
  -- [v_level] > obj.verbose_level の初期値(省略可)
  new = function(logger, v_level)
    -- logger が省略された場合は、TableDumper の定義の下に定義してある Logger を使う
    logger = logger or Logger
    
    -- 戻り値のテーブル(オブジェクト)を作成
    -- 長いですが、logger を隠すためにクロージャを使いたいので、ここにまとめて書いています･･･
    local obj = {
      -- デバッグログの出力レベル
      -- 0 でログなし
      -- 1 以上で dump() の呼び出しと終了を logger.debug() に出力します
      -- 2 以上で再帰処理の呼び出しと終了も出力します
      verbose_level = v_level or 0,
      
      -- true にするとエラーログの代わりにエラーを投げます
      strict_mode = false,
      
      -- dump() で tbl_name (テーブル名)が未指定の時に、循環参照検出時に代わりに表示する名前
      top_table_name = "<top_table>",
      
      -- 文字列を表示する時に、改行後にインデントを挿入するかどうか
      insert_indent = TableDumper.insert_indent,
      
      -- tostring() を表示する時に、改行後にインデントを挿入するかどうか。0 で insert_indent の値を使います
      insert_indent_tostring = TableDumper.insert_indent_tostring,
      
      -- キーをソートする時に用いる関数
      comparator = comparator,
      
      -- テーブルの中身を再帰的に表示する
      -- 循環参照も OK
      -- tbl:table > 中身を表示したいテーブル
      -- [tbl_name:string] > テーブル名(省略可)
      -- :string > 戻り値: テーブルの中身を表した文字列
      dump = function(self, tbl, tbl_name)
        -- ロガーを使ってデバッグログを出力します
        -- logger.debug(msg:string) を想定、使用して出力します
        local log_debug = function(level, msg)
          if self.verbose_level >= level then
            logger.debug(tostring(msg))
          end
        end
        
        log_debug(1, "dump() が呼ばれました -> tbl: " .. tostring(tbl) .. ", tbl_name: " .. tostring(tbl_name))
        
        -- tbl が table型では無かった時は、エラーメッセージを表示する
        if type(tbl) ~= "table" then
          -- tbl_name が (nil か空文字)以外の時は "引数: tbl(テーブル名)" のように表示する
          if tbl_name and tbl_name ~= "" then
            tbl_name = "(" .. tostring(tbl_name) .. ")"
          else
            tbl_name = ""
          end
          
          -- エラーメッセージを格納する変数(1つにまとめて、ログ出力を1度にする)
          local sb = string_builder.new()
          sb:append_line("関数: TableDumper.dump() でエラーが発生しました")
          self._error_arg_type(sb, "tbl" .. tbl_name, "table", type(tbl))
          
          -- エラーログを出力
          if self.strict_mode then -- strict_mode が true の時は代わりにエラーを出す
            log_debug(1, "エラーが発生したため、dump() を終了します。strict_mode なのでエラーを投げます")
            error(sb:tostring())
          else
            logger.error(sb:tostring())
            log_debug(1, "エラーが発生したため、dump() を終了します -> 戻り値: nil")
          end
          
          return nil
        end
        
        -- tbl が table型だった時の処理
        -- 結果を格納する変数(1つの string にする)
        local sb = string_builder.new()
        
        -- トップレベルの表記
        if tbl_name and tbl_name ~= "" then -- tbl_name が (nil か空文字)以外の時は "テーブル名 = {" と表示する
          tbl_name = tostring(tbl_name) -- tbl_name が string でなくても安全なように
          sb:append_line(tbl_name .. " = {")
        else -- それ以外の時は "{" と表示する
          sb:append_line("{")
          tbl_name = tostring(self.top_table_name) -- 循環参照検出時に表示する名前
        end
        
        local indent = TableDumper.INDENT_UNIT -- 最初の階層のインデント
        
        self:_inner_dump(sb, tbl, { tbl_name }, indent) -- 実際にテーブルをダンプする処理(再帰関数)
        
        sb:append("}") -- 最後にテーブルを閉じる
        
        log_debug(1, "最後に到達したので dump() を終了します")
        
        return sb:tostring() -- 結果を返す
      end,
      
      -- 実際にテーブルをダンプする関数(再帰関数)
      -- sb:string_builder > 結果を出力する string_builder
      -- tbl:table > ダンプするテーブル
      -- key:table > 引数(tbl)が格納されている変数(キー)を Top から全て溜めたもの(循環参照検出時に使う)
      -- [indent:string] > 現在のインデント(省略可)
      -- [visited:table] > 既にダンプしたテーブルの一覧(循環参照検出時に使う)(省略可)
      -- :string > 戻り値: テーブルをダンプした文字列
      _inner_dump = function(self, sb, tbl, key, indent, visited)
        -- ロガーを使ってデバッグログを出力します
        -- logger.debug(msg:string) を想定、使用して出力します
        local log_debug = function(level, msg)
          if self.verbose_level >= level then
            logger.debug(tostring(msg))
          end
        end
        
        -- 文字列用に、改行後にインデントを入れる
        local indent_lines = function(str, indent)
          return str:gsub("\n", "\n" .. indent)
        end
        
        -- キーの配列を "." で繋いで、1つの文字列にする
        local key_to_str = function(k)
          return table.concat(k, ".")
        end
        
        -- 配列 a が 配列 b を先頭から完全に含んでいるでいるかどうかを判定
        local starts_with_array = function(a, b)
          if #b > #a then
            return false
          end
          for i = 1, #b do
            if a[i] ~= b[i] then
              return false
            end
          end
          return true
        end
        
        -- 配列 array のコピーに value を追加した値を返す
        local insert_copy = function(array, value)
          local new_array = {}
          for i = 1, #array do
            new_array[i] = array[i]
          end
          table.insert(new_array, value)
          return new_array
        end
        
        log_debug(2, "_inner_dump() が呼ばれました -> key: " .. key_to_str(key))
        
        indent = tostring(indent or "")
        visited = visited or {}
        
        -- 循環参照検出時
        if visited[tbl] then
          -- 出力に循環参照を検出した旨を書いて、その先の検索を中止
          -- 循環参照か共有参照かを確認
          local ref = "共有参照"
          -- key が visited[tbl] を先頭から完全に含んでいる場合のみ循環参照
          if starts_with_array(key, visited[tbl]) then ref = "循環参照" end
          -- 出力
          sb:append_line(indent .. "* 既に表示済み(" .. ref .. ") -> " .. key_to_str(visited[tbl]))
          log_debug(2, "循環参照を検出したため、子要素の検索を中止します -> 検出したkey: " .. key_to_str(visited[tbl]))
          return
        end
        -- tbl をダンプ済みテーブルとしてマークする
        visited[tbl] = key
        
        -- ソートする
        local list = {}
        for key in pairs(tbl) do list[#list + 1] = key end
        table.sort(list, self.comparator)
        
        -- ループ
        for _, k in ipairs(list) do
          local v = tbl[k]
          -- テーブルに含まれる要素をチェックし、値の型によって動作を分ける
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
            sb:append_line(indent .. key_str .. " = {")
            self:_inner_dump(sb, v, insert_copy(key, key_str), indent .. TableDumper.INDENT_UNIT, visited) -- 再帰的呼び出し
            sb:append_line(indent .. "},")
          elseif value_type == "string" then
            local v_str = v
            local prefix = key_str .. " = \""
            -- インデントを付ける
            if self.insert_indent then
              local indent2 = indent .. string.rep(" ", #prefix) -- prefix の分も含めたインデント
              v_str = indent_lines(v_str, indent2) -- 改行後にインデントを挿入
            end
            -- 値が string の時は "" で囲んで出力
            sb:append_line(indent .. prefix .. v_str .. "\",")
          else
            -- 値がそれ以外の時は、そのまま string に変換して出力
            sb:append_line(indent .. key_str .. " = " .. tostring(v) .. ",")
          end
        end
        
        -- 最後に __tostring があるものは、それを追記する
        if has_tostring(tbl) then -- メタテーブルに __tostring が設定されている場合
          local tbl_tostring = tostring(tbl)
          local prefix = "<tostring() = \""
          -- インデントを付ける
          local insert_indent_tostring2 = self.insert_indent_tostring
          if insert_indent_tostring2 == 0 then insert_indent_tostring2 = self.insert_indent end -- 0 の時は insert_indent を使う
          if insert_indent_tostring2 then
            local indent2 = indent .. string.rep(" ", #prefix) -- "<tostring() = " の分も含めたインデント
            tbl_tostring = indent_lines(tbl_tostring, indent2) -- 改行後にインデントを挿入
          end
          -- 出力
          sb:append_line(indent .. prefix .. tbl_tostring .. "\">")
        end
        
        log_debug(2, "最後に到達したので _inner_dump() を終了します -> key: " .. key_to_str(key))
      end,
      
      -- 引数の型が違った時のエラーメッセージ
      -- sb:string_builder > テキストを出力する string_builder
      -- arg_name:string > 引数名
      -- exp_type:string > 正しい引数の型
      -- arg_type:string > 渡された引数の型
      _error_arg_type = function(sb, arg_name, exp_type, arg_type)
        sb:append("引数: " .. arg_name .. " は " .. exp_type .."型が必要です (受け取った型: " .. arg_type .. ")")
      end,
    }
    
    return obj -- dump() が入ったテーブル。ロガーが設定されている
  end,
}

-- TableDumper.new() するのが面倒な時用
-- TableDumper:dump() とすると、TableDumper._default_obj:dump() になります
-- TableDumper._default_obj は最初に TableDumper:dump() とした時だけ、TableDumper.new() が代入されます
-- print(TableDumper) とすると、ヘルプが表示されます
setmetatable(TableDumper, {
  __index = function(tbl, key)
    TableDumper._default_obj = TableDumper._default_obj or TableDumper.new()
    return TableDumper._default_obj[key]
  end,
  __tostring = function(tb)
    return [=[
<-オプション->
TableDumper.INDENT_UNIT:string -- テーブルを階層表示する時に、1階層ごとにつけるインデントです
TableDumper.insert_indent:boolean -- 文字列に改行が含まれていた時に、改行後にインデントを挿入するかどうか(new().同名オプションの初期値に使われます)
TableDumper.insert_indent_tostring:boolean or 0 -- テーブルを tostring() した文字列に改行が含まれていた時に、改行後にインデントを挿入するかどうか。0 で insert_indent の値を使います(new().同名オプションの初期値に使われます)

TableDumper.new(引数).insert_indent:boolean -- 文字列に改行が含まれていた時に、改行後にインデントを挿入するかどうか
TableDumper.new(引数).insert_indent_tostring:boolean or 0 -- テーブルを tostring() した文字列に改行が含まれていた時に、改行後にインデントを挿入するかどうか。0 で insert_indent の値を使います
TableDumper.new(引数).comparator:function -- テーブルのキーをソートする時に用いる比較用の関数。function(a, b) で a < b の時 true を返す関数
TableDumper.new(引数).verbose_level:number -- デバッグログを出したい時に設定します。1で通常、2で詳細な出力になります
TableDumper.new(引数).strict_mode:boolean -- true にするとエラーログの代わりにエラーを投げます
TableDumper.new(引数).top_table_name:string -- dump() のテーブル名を省略した場合に、代わりに表示される名前です(循環参照検出時のみ)

<-関数->
TableDumper:dump(tbl:table[, tbl_name:string]):string -- テーブル(tbl)の中身を再帰的に表した文字列を返します。循環参照も OK。テーブル名(tbl_name)は戻り値のトップレベル名と、エラー出力時に使用されます
TableDumper.new([logger:Logger, [v_level:number]]):table -- エラーメッセージなどを出力するロガーを指定します。logger.error(msg:string)、logger.debug(msg:string)という形式を想定しています。戻り値は dump() などが入ったテーブル(オブジェクト)です
TableDumper.new(引数):dump(tbl:table[, tbl_name:string]):string -- TableDumper:dump() と同じです。エラーメッセージなどが new() で指定したロガーで出力されます
]=]
  end,
})


-- ロガーを使いたい時に切り替えやすいように
Logger = {
  -- DEBUG レベルでログを出力
  debug = function(msg)
    print("Debug: " .. tostring(msg))
  end,
  
  -- ERROR レベルでログを出力
  error = function(msg)
    print("Error: " .. tostring(msg))
  end,
}

-- キーをソートする時に用いる関数
comparator = function(a, b)
  local type_a = type(a)
  local type_b = type(b)
  -- 文字列にして比較
  if (type_a == "string" or type_a == "number" or type_a == "boolean" or has_tostring(a)) and
     (type_b == "string" or type_b == "number" or type_b == "boolean" or has_tostring(b)) then
    if tostring(a) ~= tostring(b) then
      return tostring(a) < tostring(b)
    end
  end
  -- 型名を比較
  if type_a ~= type_b then
    return type_a < type_b
  end
  -- 関数ならデバッグ情報から比較
  if type_a == "function" then
    local info_a = debug.getinfo(a)
    local info_b = debug.getinfo(b)
    -- 記述されているファイル名で比較
    if info_a.source ~= info_b.source then
      return info_a.source < info_b.source
    end
    -- 記述位置で比較
    if info_a.linedefined ~= info_b.linedefined then
      return info_a.linedefined < info_b.linedefined
    end
  end
  
  return false -- それ以外は判定不可
end

return TableDumper

