------------------------------------
-- テーブルの中身を再帰的に表示する
------------------------------------

-- Version = 1.1.3

--[[ 使い方
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
      <tostring()> = "1行目
                      2行目
                      3行目"
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
    <tostring()> = "1行目
  2行目
  3行目"
  }
  文字列をコピーしたい時はこのオプションを使ってください
  
  ※ キー名に改行が含まれている場合は表示が崩れます
]]

-- table_dumper モジュールのバージョン
local VERSION = "1.1.3"

-- モジュールの読み込み
local importer = require("lazy_importer")
local string_builder = importer("string_builder") -- 文字列を継ぎ足して1つの文字列にする
local default_logger = importer.lazy_import("simple_logger") -- デフォルトで使用するロガー(遅延読み込み)

-- キーをソートする時に用いる関数
local comparator = function(a, b)
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

-- __tostring が定義されているかどうかを判定する
local has_tostring = function(value)
  local mt = getmetatable(value)
  return mt ~= nil and type(mt.__tostring) == "function"
end

---------------
-- TableDumper
---------------
-- TableDumper.new() をしないでいきなり dump() などを呼んだ時に使う
-- また、new() する時の初期値を保存するためにも使う
-- TableDumper の定義の下で setmetatable() に使っています
local default_obj

-- TableDumper.new() のオプションの初期値
local td_instance_defaults = {
  -- テーブルを表示する際の、1階層ごとにつけるインデント
  indent_unit = "  ",
  
  -- 文字列を表示する時に、改行後にインデントを挿入するかどうか
  insert_indent = true,
  
  -- tostring() を表示する時に、改行後にインデントを挿入するかどうか。0 で insert_indent の値を使います
  insert_indent_tostring = 0,
  
  -- ネストしたテーブルを表示する最大深度。-1 で制限なし
  max_depth = -1,
  -- 1つのテーブルに表示する、最大の要素の数。-1 で制限なし
  max_items_per_table = -1,
  
  -- テーブルに __tostring が設定されている時に、tostring(<テーブル>) の内容も表示するかどうか
  show_tostring = true,
  -- メタテーブルが設定されているかどうかの表示フラグ
  show_metatable = false,
  
  -- 表示をスキップするキーの型の一覧。{ function = true } のように書く。値が nil か false ならスキップしない
  ignore_key_types = {},
  -- 表示をスキップする値の型の一覧。{ function = true } のように書く。値が nil か false ならスキップしない
  ignore_value_types = {},
  -- 表示するキーを選別する関数。function(key:全ての型):boolean の形で、true を返したキーのみを表示します
  -- nil を設定すると、フィルタリングをスキップします(全て表示)
  key_filter = nil,
  -- 表示する値を選別する関数。function(value:全ての型):boolean の形で、true を返した値のみを表示します
  -- nil を設定すると、フィルタリングをスキップします(全て表示)
  value_filter = nil,
  
  -- dump() のテーブル名を省略した場合に、代わりに表示される名前(循環参照検出時のみ)
  top_table_name = "<top_table>",
  
  -- true にするとエラーログの代わりにエラーを投げます
  strict_mode = false,
  
  -- 値をダンプする直前に呼ばれるフック。function(key:全ての型, value:全ての型, key_str:string, value_str:string, key_array:table) の形で、key と value は生のキーと値、key_str と value_str は実際に表示するキーと値の文字列、key_array は親のキーから順番に子どものキーを挿入していった文字列の配列です
  on_value_dumped = nil,
  
  -- キーを string に変換する関数。function(key:全ての型, key_str:string):string という形で、key は生のキー、key_str はキーをデフォルトの変換方式で変換した文字列です。戻り値を tostring() したものを使います。function の代わりに nil を設定すると、デフォルトの変換方式で表示します
  key_formatter = nil,
  -- 値を string に変換する関数。function(value:全ての型, value_str:string):string という形で、value は生の値、value_str は値をデフォルトの変換方式で変換した文字列です。戻り値を tostring() したものを使います。function の代わりに nil を設定すると、デフォルトの変換方式で表示します
  value_formatter = nil,
  
  -- キーをソートする時に用いる関数
  comparator = comparator,
  
  -- エラーなどを出力するロガー
  -- logger.error(msg:string) または logger.debug(msg:string) という形式でログ出力をするテーブルを想定しています
  -- nil を設定すると、デフォルトのロガーが使われます
  logger = nil,
  
  -- デバッグログの出力レベル
  -- 0 でログなし
  -- 1 以上で通常のデバッグログ
  -- 2 以上でより詳細な情報
  verbose_level = 0,
}

-- TableDumper.new() のオブジェクトが使うメソッドが入ったテーブルの宣言
local methods
-- methods 内で使う関数が入ったテーブルの宣言
local helpers

-- テーブルを表示するメソッドが入った本体
local TableDumper
TableDumper = {
  -- table_dumper モジュールのバージョン
  VERSION = VERSION,
  
  -- ロガーを設定した dump() が入っているテーブル(オブジェクト)を返します
  -- [logger:Logger] > エラーなどを出力するロガー(省略可)
  --                   logger.error(msg:string) または logger.debug(msg:string) という形式でログ出力をするテーブルを想定しています
  --                   お使いのロガーと関数名などが合わない場合は、ラッパーを使用してください
  -- [verbose_level:number] > デバッグログの出力レベル(省略可)
  --                          0 でログなし
  --                          1 以上で dump() の呼び出しと終了
  --                          2 以上でより詳細な情報
  new = function(logger, verbose_level)
    -- 戻り値のテーブル(オブジェクト)を作成
    -- 関数は下で定義しています
    local obj = {}
    
    -- 作ったタイミングの初期値を設定する
    -- ※ for 文を使うと、OC 環境では動かなかった(通常環境では正しく動いた)
    -- for k, v in pairs(td_instance_defaults) do
    --   obj[k] = v
    -- end
    local template = default_obj or td_instance_defaults
    obj.indent_unit = template.indent_unit
    obj.insert_indent = template.insert_indent
    obj.insert_indent_tostring = template.insert_indent_tostring
    obj.max_depth = template.max_depth
    obj.max_items_per_table = template.max_items_per_table
    obj.show_tostring = template.show_tostring
    obj.show_metatable = template.show_metatable
    obj.ignore_key_types = template.ignore_key_types
    obj.ignore_value_types = template.ignore_value_types
    obj.key_filter = template.key_filter
    obj.value_filter = template.value_filter
    obj.top_table_name = template.top_table_name
    obj.strict_mode = template.strict_mode
    obj.on_value_dumped = template.on_value_dumped
    obj.key_formatter = template.key_formatter
    obj.value_formatter = template.value_formatter
    obj.comparator = template.comparator
    obj.logger = template.logger
    obj.verbose_level = template.verbose_level
    
    obj.logger = logger or obj.logger
    obj.verbose_level = verbose_level or obj.verbose_level
    
    -- メソッドを分ける
    setmetatable(obj, {
      __index = function(_, key)
        return methods[key]
      end,
    })
    
    return obj -- dump() が入ったオブジェクト
  end,
}

-- default_obj が無ければ生成
local get_default_obj = function()
  default_obj = default_obj or TableDumper.new()
  return default_obj
end

-- TableDumper.new() するのが面倒な時用
-- TableDumper:dump() とすると、default_obj:dump() になります
-- default_obj は最初にアクセスされた時に、TableDumper.new() を代入しています
-- TableDumper のオプションを変更すると、default_obj のオプションも変更されます
-- print(TableDumper) とすると、ヘルプが表示されます
setmetatable(TableDumper, {
  __index = function(_, key)
    return get_default_obj()[key] -- td_instance_defaults の中身は全て入っている
  end,
  
  __newindex = function(_, key, value)
    --td_instance_defaults[key] = value -- いらない
    rawset(get_default_obj(), key, value) -- default_obj の値を更新
  end,
  
  __tostring = function(_)
    return [=[
<-定数->
TableDumper.VERSION:string -- table_dumper モジュールのバージョンです。変更しないでください

<-オプション->
※ TableDumperのオプションは、全て new() に同名のオプションがあります
※ TableDumperのオプションは、new().同名オプションの初期値に使われます
TableDumper.logger:table -- エラーなどを出力するロガー。logger.error(msg:string) または logger.debug(msg:string) という形式でログ出力をするテーブルを想定しています。お使いのロガーと関数名などが合わない場合は、ラッパーを使用してください。nil を設定すると、デフォルトのロガーが使われます
※ TableDumper.new(引数).logger には nil を設定しないでください
TableDumper.verbose_level:number -- デバッグログを出したい時に設定します。0でログなし、1で通常、2で詳細な出力になります
TableDumper.indent_unit:string -- テーブルを階層表示する時に、1階層ごとにつけるインデント
TableDumper.insert_indent:boolean -- 文字列に改行が含まれていた時に、改行後にインデントを挿入するかどうか
TableDumper.insert_indent_tostring:boolean or 0 -- テーブルを tostring() した文字列に改行が含まれていた時に、改行後にインデントを挿入するかどうか。0 で insert_indent の値を使います
TableDumper.max_depth:number -- ネストしたテーブルを表示する最大深度。-1 で制限なし
TableDumper.max_items_per_table:number -- 1つのテーブルに表示する、最大の要素の数。-1 で制限なし
TableDumper.show_tostring:boolean -- テーブルに __tostring が設定されている時に、tostring(<テーブル>) の内容も表示するかどうか
TableDumper.show_metatable:boolean -- メタテーブルが設定されているかどうかの表示フラグ
TableDumper.ignore_key_types:table -- 表示をスキップするキーの型一覧。{ function = true } のように書く。値が nil か false なら表示されます
TableDumper.ignore_value_types:table -- 表示をスキップする値の型一覧。{ function = true } のように書く。値が nil か false なら表示されます
TableDumper.key_filter:function or nil -- 表示するキーを選別する関数。function(key:全ての型):boolean の形で、true を返したキーのみを表示します。nil を設定すると、フィルタリングをスキップします(全て表示)
TableDumper.value_filter:function or nil -- 表示する値を選別する関数。function(value:全ての型):boolean の形で、true を返した値のみを表示します。nil を設定すると、フィルタリングをスキップします(全て表示)
TableDumper.comparator:function or nil -- テーブルのキーをソートする時に用いる比較用の関数。function(a:全ての型, b:全ての型):boolean の形式で a < b の時 true を返す関数
TableDumper.top_table_name:string -- dump() のテーブル名を省略した場合に、代わりに表示される名前(循環参照検出時のみ)
TableDumper.strict_mode:boolean -- true にするとエラーログの代わりにエラーを投げます
TableDumper.on_value_dumped:function or nil -- 値をダンプする直前に呼ばれるフック。function(key:全ての型, value:全ての型, key_str:string, value_str:string, key_array:table) の形で、key と value は生のキーと値、key_str と value_str は実際に表示するキーと値の文字列、key_array は親のキーから順番に子どものキーを挿入していった文字列の配列です
TableDumper.key_formatter:function or nil -- キーを string に変換する関数。function(key:全ての型, key_str:string):string という形式で、key は生のキー、key_str はキーをデフォルトの変換方式で変換した文字列です。戻り値を tostring() したものを使います。function の代わりに nil を設定すると、デフォルトの変換方式で表示します
TableDumper.value_formatter:function or nil -- 値を string に変換する関数。function(value:全ての型, value_str:string):string という形式で、value は生の値、value_str は値をデフォルトの変換方式で変換した文字列です。戻り値を tostring() したものを使います。function の代わりに nil を設定すると、デフォルトの変換方式で表示します

<-関数->
TableDumper:dump(tbl:table[, tbl_name:string]):string -- テーブル(tbl)の中身を再帰的に表した文字列を返します。循環参照も OK。テーブル名(tbl_name)は戻り値のトップレベル名と、エラー出力時に使用されます
TableDumper.new([logger:ロガー, [v_level:number]]):table -- オプションを個別に設定できます。戻り値は dump() などが入ったテーブル(オブジェクト)です
TableDumper.new(引数):dump(tbl:table[, tbl_name:string]):string -- TableDumper:dump() と同じです。個別に設定したオプションを使ってダンプします
]=]
  end,
})

-- 文字列をダンプするメソッドが入ったテーブル
methods = {
  -- テーブルの中身を再帰的に表示する(循環参照も OK)
  -- tbl:table > 中身を表示したいテーブル
  -- [tbl_name:string] > テーブル名(省略可)
  -- :string > テーブルの中身を表した文字列(戻り値)
  dump = function(self, tbl, tbl_name)
    -- ロガーを使ってデバッグログを出力する関数
    -- logger.debug(msg:string) を想定、使用して出力します
    local log_debug = function(level, msg)
      if self.verbose_level >= level then
        self.logger.debug(tostring(msg))
      end
    end
    
    -- ロガーを使ってエラーログを出力する関数
    -- logger.error(msg:string) を想定、使用して出力します
    local log_error = function(sb, do_log_debug)
      if do_log_debug == nil then do_log_debug = true end
      local err_msg = sb:tostring():gsub("\n+$", "")
      
      if self.strict_mode then -- strict_mode が true の時は代わりにエラーを投げる
        if do_log_debug then
          log_debug(1, "エラーが発生したため、dump() を終了します。strict_mode なのでエラーを投げます")
        end
        error(err_msg)
      else
        self.logger.error(err_msg)
        if do_log_debug then
          log_debug(1, "エラーが発生したため、dump() を終了します -> 戻り値: nil")
        end
      end
    end
    
    -- 間違えて dumper.dump() と呼んでいないかチェック(:dump() が正しい)
    if not self or
       type(self.dump) ~= "function" or
       type(self._inner_dump) ~= "function" then
      error("関数: TableDumper:dump() でエラーが発生しました\n:dump() で呼んでください(.dump() で呼ばれました)")
    end
    
    -- ロガーのチェック
    if self.logger == nil then
      -- logger が省略された場合は、default_logger を使う
      self.logger = default_logger
    end
    if type(self.logger) ~= "table" then
      error("関数: TableDumper:dump() でエラーが発生しました\nロガーがテーブルではありません -> 型: " .. type(self.logger))
    elseif type(self.logger.error) ~= "function" then
      error("関数: TableDumper:dump() でエラーが発生しました\n<ロガー>.error が関数ではありません -> 型: " .. type(self.logger.error))
    elseif type(self.logger.debug) ~= "function" then
      error("関数: TableDumper:dump() でエラーが発生しました\n<ロガー>.debug が関数ではありません -> 型: " .. type(self.logger.debug))
    end
    
    -- メッセージを格納する変数(1つにまとめて、ログ出力を1度にする)
    local sb = string_builder.new()
    
    -- verbose_level は先にチェック
    local v_level_type = type(self.verbose_level)
    if v_level_type ~= "number" then
      sb:append_line("関数: TableDumper:dump() でエラーが発生しました")
      sb:append_line("オプション: verbose_level は number型が必要です(現在の型: " .. v_level_type ..")")
      log_error(sb, false) -- エラーログを出力
      return nil
    end
    
    log_debug(1, "dump() が呼ばれました -> tbl: " .. tostring(tbl) .. ", tbl_name: " .. tostring(tbl_name))
    
    -- オプションの型チェック
    local result = self:_option_type_check(sb)
    if not result then
      log_error(sb) -- エラーログを出力
      return nil
    end
    
    -- tbl が table型では無かった時は、エラーメッセージを表示する
    if type(tbl) ~= "table" then
      -- tbl_name が (nil か空文字)以外の時は "引数: tbl(テーブル名)" のように表示する
      if tbl_name and tbl_name ~= "" then
        tbl_name = "(" .. tostring(tbl_name) .. ")"
      else
        tbl_name = ""
      end
      
      -- エラーメッセージを格納する変数(1つにまとめて、ログ出力を1度にする)
      sb = string_builder.new()
      sb:append_line("関数: TableDumper:dump() でエラーが発生しました")
      sb:append("引数: tbl" .. tbl_name .. " は table型が必要です(受け取った型: " .. type(tbl) .. ")")
      
      log_error(sb) -- エラーログを出力
      return nil
    end
    
    -- tbl が table型だった時の処理
    -- 結果を格納する変数(1つの string にする)
    sb = string_builder.new()
    
    -- トップレベルの表記
    if tbl_name and tbl_name ~= "" then -- tbl_name が (nil か空文字)以外の時は "テーブル名 = {" と表示する
      tbl_name = tostring(tbl_name) -- tbl_name が string でなくても安全なように
      sb:append_line(tbl_name .. " = {")
    else -- それ以外の時は "{" と表示する
      sb:append_line("{")
      tbl_name = tostring(self.top_table_name) -- 循環参照検出時に表示する名前
    end
    
    local indent = self.indent_unit -- 最初の階層のインデント
    
    self:_inner_dump(sb, tbl, { tbl_name }, indent) -- 実際にテーブルをダンプする処理(再帰関数)
    
    sb:append("}") -- 最後にテーブルを閉じる
    
    log_debug(1, "最後に到達したので dump() を終了します")
    
    return sb:tostring() -- 結果を返す
  end,
  
  -- 実際にテーブルをダンプする関数(再帰関数)
  -- sb:string_builder > 結果を出力する string_builder
  -- tbl:table > ダンプするテーブル
  -- key:table > 親から辿ってきたキー名が全て入った配列(循環参照検出時に使う)
  -- indent:string > 現在のインデント
  -- [visited:table] > 既にダンプしたテーブルの一覧(循環参照検出時に使う)(省略可)
  -- :string > テーブルをダンプした文字列(戻り値)
  _inner_dump = function(self, sb, tbl, key, indent, visited)
    -- ロガーを使ってデバッグログを出力する関数
    -- logger.debug(msg:string) を想定、使用して出力します
    local log_debug = function(level, msg)
      if self.verbose_level >= level then
        self.logger.debug(tostring(msg))
      end
    end
    
    -- formatter を呼ぶ関数
    local _format_data = function(data, data_str, kind)
      local formatted_data = data_str
      -- formatter を設定
      local formatter = self.key_formatter
      if kind == "value" then formatter = self.value_formatter end
      
      -- 変換
      if formatter then
        formatted_data = tostring(formatter(data, data_str))
        -- ログを出す
        if formatted_data ~= data_str then
          local kind_name = "キー"
          if kind == "value" then kind_name = "値" end
          log_debug(2, kind .. "_formatter で" .. kind_name .. "が変換されました -> " .. kind .. ": " .. data_str .. " → " .. formatted_data)
        end
      end
      
      return formatted_data
    end
    -- key_formatter を呼ぶ関数
    local format_key = function(k, k_str)
      return _format_data(k, k_str, "key")
    end
    -- value_formatter を呼ぶ関数
    local format_value = function(v, value_str)
      return _format_data(v, value_str, "value")
    end
    
    -- フックを呼ぶ関数
    local call_hook = function(k, v, key_str, value_str, key_array)
      if self.on_value_dumped then
        self.on_value_dumped(k, v, key_str, value_str, key_array)
      end
    end
    
    log_debug(2, "_inner_dump() が呼ばれました -> key: " .. helpers.key_to_str(key))
    
    visited = visited or {}
    
    -- 最大深度判定
    if self.max_depth >= 0 and #key > self.max_depth then
      sb:append_line(indent .. "( 最大深度に到達 )")
      log_debug(1, "最大深度に到達したため、要素の検索を中止します -> key: " .. helpers.key_to_str(key))
      return
    end
    
    -- 循環参照検出時
    if visited[tbl] then
      -- 出力に循環参照を検出した旨を書いて、その先の検索を中止
      -- 循環参照か共有参照かを確認
      local ref = "共有参照"
      -- key が visited[tbl] を先頭から完全に含んでいる場合のみ循環参照
      if helpers.starts_with_array(key, visited[tbl]) then ref = "循環参照" end
      -- 出力
      sb:append_line(indent .. "* 既に表示済み(" .. ref .. ") -> " .. helpers.key_to_str(visited[tbl]))
      log_debug(2, ref .. "を検出したため、要素の検索を中止します -> 検出したkey: " .. helpers.key_to_str(visited[tbl]) .. " 現在のkey: " .. helpers.key_to_str(key))
      return
    end
    -- tbl をダンプ済みテーブルとしてマークする
    visited[tbl] = key
    
    -- ソートする
    local list = {}
    for key2, _ in pairs(tbl) do list[#list + 1] = key2 end
    if self.comparator then table.sort(list, self.comparator) end
    
    -- ループ
    local count = 1
    for _, k in ipairs(list) do
      -- 1つのテーブルに表示する最大要素数に達したら、ループを抜ける
      if self.max_items_per_table >= 0 and count > self.max_items_per_table then
        sb:append_line(indent .. "=== AND MORE ===")
        log_debug(1, "最大要素数に到達したため、要素の検索を中止します -> key: " .. helpers.key_to_str(key))
        break
      end
      
      local v = tbl[k]
      
      -- スキップする型に設定されていたら何も書かない
      if self.ignore_key_types and self.ignore_key_types[type(k)] then
        log_debug(1, "ignore_key_types によりスキップされました -> key: " .. tostring(k) .. ", type: " .. type(k))
      else
      -- ignore_value_types によるスキップ
      if self.ignore_value_types and self.ignore_value_types[type(v)] then
        log_debug(1, "ignore_value_types によりスキップされました -> value: " .. tostring(v) .. ", type: " .. type(v))
      else
      -- key_filter によるスキップ
      if self.key_filter and not self.key_filter(k) then
        log_debug(1, "key_filter によりスキップされました -> key: " .. tostring(k))
      else
      -- value_filter によるスキップ
      if self.value_filter and not self.value_filter(v) then
        log_debug(1, "value_filter によりスキップされました -> value: " .. tostring(v))
      else
        count = count + 1
        -- テーブルに含まれる要素をチェックし、値の型によって動作を分ける
        local key_str = tostring(k) -- キー名を結合できるように string にする
        -- キーが string の時は "" で囲む
        if type(k) == "string" then
          key_str = "\"" .. key_str .. "\""
        end
        
        local value_type = type(v)
        if value_type == "table" then
          -- 値がテーブルの時は、再帰的に子要素を検索
          -- key_formatter を呼ぶ
          key_str = format_key(k, key_str)
          
          local sb2 = string_builder.new()
          sb:append(indent .. key_str .. " = ")
          sb2:append_line("{")
          --------------------------------
          -- 再帰的呼び出し(子要素を検索)
          self:_inner_dump(sb2, v, helpers.insert_copy(key, key_str), indent .. self.indent_unit, visited)
          --------------------------------
          sb2:append(indent .. "}")
          
           -- value_formatter を呼ぶ
          local value_str = format_value(v, sb2:tostring())
          -- フックを呼ぶ
          call_hook(k, v, key_str, value_str, helpers.insert_copy(key, key_str))
          -- 出力
          sb:append_line(value_str .. ",")
        elseif value_type == "string" or has_tostring(v) then
          -- has_tostring(v) のチェックは debug.setmetatable() で設定した時用
          local value_str = tostring(v)
          if value_type ~= "string" then
            key_str = "tostring([" .. key_str .. "])"
          end
          
          -- key_formatter を呼ぶ
          key_str = format_key(k, key_str)
          local prefix = key_str .. " = "
          
          -- インデントを付ける
          if self.insert_indent then
            local indent2 = indent .. string.rep(" ", #prefix + 1) -- prefix と " の分も含めたインデント
            value_str = helpers.indent_lines(value_str, indent2) -- 改行後にインデントを挿入
          end
          -- 値が string の時は "" で囲む
          value_str = "\"" .. value_str .. "\""
          
          -- value_formatter を呼ぶ
          value_str = format_value(v, value_str)
          
          -- フックを呼ぶ
          call_hook(k, v, key_str, value_str, helpers.insert_copy(key, key_str))
          
          -- 出力
          sb:append_line(indent .. prefix .. value_str .. ",")
        else
          -- 値がそれ以外の時は、そのまま string に変換して出力
          -- key_formatter を呼ぶ
          key_str = format_key(k, key_str)
          -- value_formatter を呼ぶ
          local value_str = format_value(v, tostring(v))
          
          -- フックを呼ぶ
          call_hook(k, v, key_str, value_str, helpers.insert_copy(key, key_str))
          
          sb:append_line(indent .. key_str .. " = " .. value_str .. ",")
        end
      end
      end
      end
      end
    end
    
    -- __tostring があるものは、それを追記する
    if self.show_tostring and has_tostring(tbl) then -- メタテーブルに __tostring が設定されている場合
      local tbl_tostring = tostring(tbl)
      local prefix = "<tostring()> = \""
      -- インデントを付ける
      local insert_indent_tostring2 = self.insert_indent_tostring
      if insert_indent_tostring2 == 0 then insert_indent_tostring2 = self.insert_indent end -- 0 の時は insert_indent を使う
      if insert_indent_tostring2 then
        local indent2 = indent .. string.rep(" ", #prefix) -- "<tostring() = " の分も含めたインデント
        tbl_tostring = helpers.indent_lines(tbl_tostring, indent2) -- 改行後にインデントを挿入
      end
      -- 出力
      sb:append_line(indent .. prefix .. tbl_tostring .. "\"")
    end
    
    -- show_metatable が true の時はメタテーブルも表示する
    if self.show_metatable then
      -- メタテーブルを取得
      list = {}
      local mt = getmetatable(tbl) or {}
      for key2, _ in pairs(mt) do list[#list + 1] = key2 end
      -- メタテーブルが 1つ以上設定されているときだけ表示
      if #list > 0 then
        -- メタテーブルをソートする
        if self.comparator then table.sort(list, self.comparator) end
        
        -- 出力
        sb:append_line(indent .. "<metatable> = {")
        -- キーが設定済みかどうかだけ書く
        for _, k in ipairs(list) do
          sb:append_line(indent .. self.indent_unit .. tostring(k) .. " : 設定済み")
        end
        sb:append_line(indent .. "}")
      end
    end
    
    log_debug(2, "最後に到達したので _inner_dump() を終了します -> key: " .. helpers.key_to_str(key))
  end,
  
  -- 全てのオプションの型チェックをする
  _option_type_check = function(self, sb)
    -- 一度エラーを出したかどうかのフラグ
    local errored = false
    -- 型をチェックし、エラーを出す
    local type_check = function(option_name, option_type, type1, allow_nil, type2)
      if option_type ~= type1 and option_type ~= type2 then
        if not allow_nil or option_type ~= "nil" then
          local exp_type = type1 .. "型"
          if type2 then exp_type = exp_type .. " または " .. type2 .. "型" end
          if allow_nil then exp_type = exp_type .. " または nil " end
          -- エラーを出力する
          if not errored then
            sb:append_line("関数: TableDumper:dump() でエラーが発生しました")
            errored = true
          end
          sb:append_line("オプション: " .. option_name .. " は " .. exp_type .. "が必要です(現在の型: " .. option_type ..")")
          
          return false
        end
      end
      
      return true
    end
    
    local result = true
    result = type_check("indent_unit", type(self.indent_unit), "string") and result
    result = type_check("insert_indent", type(self.insert_indent), "boolean", true) and result
    result = type_check("insert_indent_tostring", type(self.insert_indent_tostring), "boolean", true, "number") and result
    result = type_check("max_depth", type(self.max_depth), "number") and result
    result = type_check("max_items_per_table", type(self.max_items_per_table), "number") and result
    result = type_check("show_tostring", type(self.show_tostring), "boolean", true) and result
    result = type_check("show_metatable", type(self.show_metatable), "boolean", true) and result
    result = type_check("ignore_key_types", type(self.ignore_key_types), "table", true) and result
    result = type_check("ignore_value_types", type(self.ignore_value_types), "table", true) and result
    result = type_check("key_filter", type(self.key_filter), "function", true) and result
    result = type_check("value_filter", type(self.value_filter), "function", true) and result
    result = type_check("strict_mode", type(self.strict_mode), "boolean", true) and result
    result = type_check("top_table_name", type(self.top_table_name), "string") and result
    result = type_check("on_value_dumped", type(self.on_value_dumped), "function", true) and result
    result = type_check("key_formatter", type(self.key_formatter), "function", true) and result
    result = type_check("value_formatter", type(self.value_formatter), "function", true) and result
    result = type_check("comparator", type(self.comparator), "function", true) and result
    
    return result
  end,
}

helpers = {
  -- 文字列用に、改行後にインデントを入れる
  indent_lines = function(str, indent)
    return str:gsub("\n", "\n" .. indent)
  end,
  
  -- キーの配列を "." で繋いで、1つの文字列にする
  key_to_str = function(k)
    return table.concat(k, ".")
  end,
  
  -- 配列 a が 配列 b を先頭から完全に含んでいるでいるかどうかを判定
  starts_with_array = function(a, b)
    if #b > #a then
      return false
    end
    for i = 1, #b do
      if a[i] ~= b[i] then
        return false
      end
    end
    return true
  end,
  
  -- 配列 array のコピーに value を追加した値を返す
  insert_copy = function(array, value)
    local new_array = {}
    for i = 1, #array do
      new_array[i] = array[i]
    end
    table.insert(new_array, value)
    return new_array
  end,
}

return TableDumper
