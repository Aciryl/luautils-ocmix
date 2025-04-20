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
  ※ 遅延読み込みの場合、メタテーブルは変更できません(プロキシへの変更になってしまうので)
  -> メタテーブルを使いたい場合は、
     local lazy_module = importer(<モジュール名>, true, force_reload:boolean, true)
     または
     local lazy_module = importer.lazy_import_no_proxy(<モジュール名>)
     を使ってください
     この場合モジュールを使う時は lazy_module().xxx としてください
  ※ 遅延読み込みの場合、オプションの値はモジュールを読み込む時の値ではなく import をした時点の値を使うので注意(logger, change_message, msg_handler)
  
  強制再読み込み
  local reloaded_module = importer(<モジュール名>, false, true) -- 通常の読み込み
  または
  local reloaded_module = importer(<モジュール名>, true, true) -- 遅延読み込み
  
  ロガーの設定(オプション)
  importer.logger = <ロガー> -- インポートされたタイミングでメッセージが出力されます
  ※ ロガーは <ロガー>.debug(msg:string) -- の形式でログ出力するものを想定しています
  
  エラーメッセージについて
  importer.change_message = false とするとデフォルトのエラーメッセージが表示されます
  importer.msg_handler に function(original_err:string, module_name:string) の関数を設定すると、エラーメッセージの処理を変更できます
]]

-- 関数の宣言
local load_module -- 実際に読み込む関数
 -- メッセージを変更する関数
local msg_handler = function(original_err, module_name)
  if original_err:match("module '" .. module_name .. "' not found") then
    error("モジュールが見つかりません: " .. module_name)
  else
    error("モジュールの読み込み中にエラーが発生しました:\n" .. original_err)
  end
end

-- 本体
local LazyImporter
LazyImporter = {
  logger = nil, -- ロガー(オプション)
  change_message = true, -- モジュール読み込み時のエラーメッセージに手を加えるか
  msg_handler = msg_handler, -- メッセージを変更するメソッド
  
  -- モジュールを読み込む関数
  import = function(module_name, lazy_load, force_reload, no_proxy)
    if type(module_name) ~= "string" then
      error("モジュール名は string型が必要です (現在の型: " .. type(module_name) ..")")
    end
    
    local logger = LazyImporter.logger
    local change_message = LazyImporter.change_message
    local msg_handler = LazyImporter.msg_handler
    
    if not lazy_load then
      -- lazy でなければ普通に読み込み
      return load_module(module_name, force_reload, logger, change_message, msg_handler)
    else
      -- lazy の時は、アクセスされた時に読み込み
      local _module  -- モジュールのキャッシュ
      -- モジュールがロードされていなければロードする
      local get_module = function()
        if _module == nil then
          -- アクセスされた時に読み込み
          _module = load_module(module_name, force_reload, logger, change_message, msg_handler)
        end
        return _module
      end
      
      if no_proxy then
        -- プロキシを使わない場合
        return get_module -- 関数自体を返す(モジュール名() でアクセス)
      else
        -- プロキシを使う場合
        -- 遅延読み込み用のプロキシモジュール
        local proxy_module = setmetatable({}, {
          __index = function(_, key)
            return get_module()[key]
          end,
          
          __newindex = function(_, key, value)
            get_module()[key] = value
          end,
          
          __pairs = function()
            return pairs(get_module())
          end,
          
          __ipairs = function()
            return ipairs(get_module())
          end,
          
          __call = function(_, ...)
            return get_module()(...)
          end,
          
          __tostring = function(_)
            return tostring(get_module())
          end,
          
          __metatable = false, -- メタテーブルを変更不可にする
        })
        
        return proxy_module
      end
    end
  end,
  
  lazy_import = function(module_name, force_reload)
    return LazyImporter.import(module_name, true, force_reload)
  end,
  
  lazy_import_no_proxy = function(module_name, force_reload)
    return LazyImporter.import(module_name, true, force_reload, true)
  end,
}

-- __call に対応
setmetatable(LazyImporter, {
  __call = function(self, ...)
    return self.import(...)
  end,
})

-- 実際に読み込む関数の実装
load_module = function(module_name, force_reload, logger, change_message, msg_handler)
  -- force_reload の時はキャッシュをクリア
  if force_reload then
    package.loaded[module_name] = nil
  end
  
  -- 既に読み込み済みの場合は、キャッシュされたものを返す
  if package.loaded[module_name] then
    return package.loaded[module_name]
  end
  
  local ok, result_or_err = pcall(require, module_name)
  if not ok then
    if change_message and type(msg_handler) == "function" then
      -- メッセージハンドラに任せる
      msg_handler(result_or_err, module_name)
    else
      -- メッセージを変更しない場合はそのままのエラーを出す
      error(result_or_err)
    end
  end
  
  -- ログ出力
  if logger and type(logger.debug) == "function" then
    logger.debug("モジュールが読み込まれました -> モジュール名: " .. module_name)
  end
  
  return result_or_err
end

return LazyImporter

