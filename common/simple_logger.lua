--------------------
-- シンプルなロガー
--------------------
--[[ 使い方
  -- 初期化
  local logger = require("simple_logger")
  logger.log_level = logger.INFO -- info 以上を出力
  
  -- ログの出力
  logger.debug("aaa") -> 出力されない
  logger.info("aaa") -> Info : aaa
  logger.warn("aaa") -> Warn : aaa
  logger.error("aaa") -> Error : aaa
  logger.fatal("aaa") -> Fatal : aaa
  
  -- logger.log を使う場合
  logger.log_level = logger.DEBUG -- debug 以上を出力
  logger.log(logger.DEBUG, "aaa") -> Debug: aaa
  logger.log(logger.INFO, "aaa") -> Info : aaa
  ...
]]

-- 本体
local Logger
Logger = {
  -- ログレベル定数
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
  FATAL = 4,
  
  -- 現在のログレベル
  log_level = 0, -- DEBUG
  
  -- レベルを指定してログを出力
  log = function(level, msg)
    if level == Logger.DEBUG then
      Logger.debug(msg)
    elseif level == Logger.INFO then
      Logger.info(msg)
    elseif level == Logger.WARN then
      Logger.warn(msg)
    elseif level == Logger.ERROR then
      Logger.error(msg)
    elseif level == Logger.FATAL then
      Logger.fatal(msg)
    end
  end,
  
  -- DEBUG レベルでログを出力
  debug = function(msg)
    if Logger.log_level <= Logger.DEBUG then
      print("Debug: " .. tostring(msg))
    end
  end,
  
  -- INFO レベルでログを出力
  info = function(msg)
    if Logger.log_level <= Logger.INFO then
      print("Info : " .. tostring(msg))
    end
  end,
  
  -- WARN レベルでログを出力
  warn = function(msg)
    if Logger.log_level <= Logger.WARN then
      print("Warn : " .. tostring(msg))
    end
  end,
  
  -- ERROR レベルでログを出力
  error = function(msg)
    if Logger.log_level <= Logger.ERROR then
      print("Error: " .. tostring(msg))
    end
  end,
  
  -- FATAL レベルでログを出力
  fatal = function(msg)
    if Logger.log_level <= Logger.FATAL then
      print("Fatal: " .. tostring(msg))
    end
  end,
}

return Logger