--------------------------------
-- モジュールを遅延読み込みする
--------------------------------
--[[ 使い方
  初期化
  local importer = require("lazy_importer")
  
  通常の読み込み
  local my_module = importer(<モジュール名>)
  または
  local my_module = importer.import(<モジュール名>)
  
  遅延読み込み
  local lazy_module = importer(<モジュール名>, true)
  または
  local lazy_module = importer.lazy_import(<モジュール名>)
  ※ 遅延読み込みの場合、setmetatable(lazy_module, {}) は使えません(プロキシへの変更になってしまうので)
  -> メタテーブルを変更したい場合は、
     local lazy_module_no_proxy = importer(<モジュール名>, true, force_reload:boolean, true)
     または
     local lazy_module_no_proxy = importer.lazy_import_no_proxy(<モジュール名>)
     として
     setmetatable(lazy_module_no_proxy(), {})
     を使ってください
     プロキシの代わりに get_module 関数を返すようになります
     この場合モジュールを使う時は lazy_module_no_proxy().xxx としてください
     -> lazy_module.xxx の形式で使いたいけど setmetatable したい時は、
        setmetatable(importer.get_module(lazy_module), {})
        でメタテーブルを設定することもできます
  ※ __close, __gc は、モジュールに __metatable が定義されていると使えません
  ※ 読み込むモジュールの __mode は適用されません
  ※ 遅延読み込みの場合、オプションの値はモジュールを読み込む時の値ではなく import をした時点の値を使うので注意(logger, err_msg_formatter)
  ※ 明示的に遅延読み込みをトリガーしたい場合は、importer.get_module(lazy_module) でできます
  
  強制再読み込み
  local reloaded_module = importer(<モジュール名>, false, true) -- 通常の読み込み
  または
  local reloaded_module = importer(<モジュール名>, true, true) -- 遅延読み込み
  
  ロガーの設定(オプション)
  importer.logger = <ロガー> -- インポートされたタイミングでメッセージが出力されます
  ※ ロガーは <ロガー>.debug(msg:string) -- の形式でログ出力するものを想定しています
  
  エラーメッセージについて
  importer.err_msg_formatter に function(original_err_msg:string, module_name:string):string の関数を設定すると、エラーメッセージを変更できます
]]

-- 関数の宣言
local load_module -- 実際にモジュールを読み込む関数

-- テーブルの宣言
local proxy_cache = setmetatable({}, { __mode = "v" }) -- proxy_num からプロキシを取得するためのテーブル
local proxy_count = 0 -- 次の proxy_cache の番号取得に使う
local proxy2get_module = setmetatable({}, { __mode = "k" }) -- プロキシから get_module を取得するためのテーブル
local proxy2module = setmetatable({}, { -- プロキシからモジュールを取得するためのテーブル
  __index = function(_, key) -- プロキシが登録されて無ければ、get_module を試す
    local get_module = proxy2get_module[key]
    if get_module then return get_module.get_module() end
    return key -- プロキシじゃなければそのまま返す
  end,
  __mode = "kv",
})
local proxy_mt -- 全プロキシ共通のメタテーブル

-- 本体
local LazyImporter
LazyImporter = {
  logger = nil, -- ロガー(オプション)
  err_msg_formatter = nil, -- メッセージを変更するメソッド(オプション)
  
  -- モジュールを読み込む関数
  import = function(module_name, lazy_load, force_reload, no_proxy)
    if type(module_name) ~= "string" then
      error("モジュール名は string型が必要です(現在の型: " .. type(module_name) ..")")
    end
    
    -- 設定をコピー
    local logger = LazyImporter.logger
    local err_msg_formatter = LazyImporter.err_msg_formatter
    
    if not lazy_load then
      -- lazy でなければ普通に読み込み
      return load_module(module_name, force_reload, logger, err_msg_formatter)
    else
      -- lazy の時は、アクセスされた時に読み込み
      if no_proxy then
        local _module  -- モジュールのキャッシュ
        -- プロキシを使わない場合
        local get_module = function() -- モジュールを取得
          if _module == nil then
            -- アクセスされた時に読み込み
            _module = load_module(module_name, force_reload, logger, err_msg_formatter)
            -- 不要になった参照を明示的に解放
            logger = nil
            err_msg_formatter = nil
          end
          return _module
        end
        
        return get_module -- 関数自体を返す(モジュール名() でアクセス)
      else
        -- プロキシを使う場合
        local proxy_num = proxy_count + 1
        proxy_count = proxy_num
        local get_module = function() -- モジュールを取得
          local proxy = proxy_cache[proxy_num]
          local ops = proxy2get_module[proxy].ops
          -- アクセスされた時に読み込み
          local _module = load_module(ops.module_name, ops.force_reload, ops.logger, ops.err_msg_formatter)
          proxy2module[proxy] = _module -- プロキシからモジュールを取得できるように
          -- 不要になった参照を明示的に解放
          proxy2get_module[proxy] = nil
          return _module
        end
        
        -- プロキシを作成
        local proxy = setmetatable({}, proxy_mt)
        proxy_cache[proxy_num] = proxy
        proxy2get_module[proxy] = {
          get_module = get_module,
          ops = {
            module_name = module_name,
            force_reload = force_reload,
            logger = logger,
            err_msg_formatter = err_msg_formatter,
          },
        }
        -- 遅延読み込み用のプロキシモジュールを返す
        return proxy
      end
    end
  end,
  
  lazy_import = function(module_name, force_reload)
    return LazyImporter.import(module_name, true, force_reload)
  end,
  
  lazy_import_no_proxy = function(module_name, force_reload)
    return LazyImporter.import(module_name, true, force_reload, true)
  end,
  
  get_module = function(proxy)
    return proxy2module[proxy]
  end,
}

-- __call に対応
setmetatable(LazyImporter, {
  __call = function(self, ...)
    return self.import(...)
  end,
})

-- 実際に読み込む関数の実装
load_module = function(module_name, force_reload, logger, err_msg_formatter)
  -- force_reload の時はキャッシュをクリア
  if force_reload then
    package.loaded[module_name] = nil
  -- 既に読み込み済みの場合は、キャッシュされたものを返す
  elseif package.loaded[module_name] then
    return package.loaded[module_name]
  end
  
  local ok, result_or_err = pcall(require, module_name)
  if not ok then
    if type(err_msg_formatter) == "function" then
      -- メッセージハンドラに任せる
      error(err_msg_formatter(result_or_err, module_name))
    else
      -- メッセージを変更しない場合はそのままのエラーを出す
      error(result_or_err)
    end
  end
  
  -- ログ出力
  if type(logger) == "table" and type(logger.debug) == "function" then
    logger.debug("モジュールが読み込まれました -> モジュール名: " .. module_name)
  end
  
  return result_or_err
end

-- プロキシに設定する共通のメタテーブル
proxy_mt = {
  -- フィールドアクセス系
  __index = function(self, key)
    return proxy2module[self][key]
  end,
  __newindex = function(self, key, value)
    proxy2module[self][key] = value
  end,
  __pairs = function(self)
    return pairs(proxy2module[self])
  end,
  __ipairs = function(self)
    return ipairs(proxy2module[self])
  end,
  
  -- 算術演算系
  __add = function(a, b)
    return proxy2module[a] + proxy2module[b]
  end,
  __sub = function(a, b)
    return proxy2module[a] - proxy2module[b]
  end,
  __mul = function(a, b)
    return proxy2module[a] * proxy2module[b]
  end,
  __div = function(a, b)
    return proxy2module[a] / proxy2module[b]
  end,
  __idiv = function(a, b)
    return proxy2module[a] // proxy2module[b]
  end,
  __mod = function(a, b)
    return proxy2module[a] % proxy2module[b]
  end,
  __pow = function(a, b)
    return proxy2module[a] ^ proxy2module[b]
  end,
  __unm = function(a)
    return -proxy2module[a]
  end,
  
  -- 比較系
  __eq = function(a, b)
    return proxy2module[a] == proxy2module[b]
  end,
  __lt = function(a, b)
    return proxy2module[a] < proxy2module[b]
  end,
  __le = function(a, b)
    return proxy2module[a] <= proxy2module[b]
  end,
  
  -- ビット演算系
  __band = function(a, b)
    return proxy2module[a] & proxy2module[b]
  end,
  __bor = function(a, b)
    return proxy2module[a] | proxy2module[b]
  end,
  __bxor = function(a, b)
    return proxy2module[a] ~ proxy2module[b]
  end,
  __bnot = function(a)
    return ~proxy2module[a]
  end,
  __shl = function(a, b)
    return proxy2module[a] << proxy2module[b]
  end,
  __shr = function(a, b)
    return proxy2module[a] >> proxy2module[b]
  end,
  
  -- その他
  __call = function(self, ...)
    return proxy2module[self](...)
  end,
  __tostring = function(self)
    return tostring(proxy2module[self])
  end,
  __len = function(self)
    return #proxy2module[self]
  end,
  __concat = function(a, b)
    return proxy2module[a] .. proxy2module[b]
  end,
  -- __close, __gc は、モジュールに __metatable が定義されていると使えない
  __close = function(self, err)
    local module = proxy2module[self]
    local mt = getmetatable(module)
    if type(mt) == "table" and type(mt.__close) == "function" then
      mt.__close(module, err)
    end
  end,
  __gc = function(self)
    local module = proxy2module[self]
    local mt = getmetatable(module)
    if type(mt) == "table" and type(mt.__gc) == "function" then
      mt.__gc(module)
    end
  end,
  
  __metatable = false, -- メタテーブル変更不可
  
  -- __name は関数ではないので、
  -- 最初にモジュールの __name を読み取ろうとすると、モジュールを即読み込んでしまい、遅延読み込みにならない
  
  -- __mode は最初からプロキシに設定しないと適用されない
  -- 最初にモジュールの __mode を読み取ろうとすると、モジュールを即読み込んでしまい、遅延読み込みにならない
}

return LazyImporter

