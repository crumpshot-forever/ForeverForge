"use strict";

const fs = require("fs");
const path = require("path");
const fengari = require("../../vulture/node_modules/fengari");

const lua = fengari.lua;
const lauxlib = fengari.lauxlib;
const lualib = fengari.lualib;
const toLua = fengari.to_luastring;

const root = path.resolve(__dirname, "..");
const testPath = path.join(__dirname, "ready-turnins.test.lua");
const source = fs.readFileSync(testPath);
function luaLong(text) {
  const delimiter = "]==]";
  if (text.indexOf(delimiter) !== -1) {
    throw new Error("addon source contains the Lua long-string delimiter");
  }
  return "[==[" + text + "]==]";
}
const prelude =
  "TURNIN_SRC = " + luaLong(fs.readFileSync(path.join(root, "Modules", "ReadyTurnins.lua"), "utf8")) + "\n";

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function loadChunk(name, text) {
  const body = Buffer.isBuffer(text) ? text : Buffer.from(text);
  if (lauxlib.luaL_loadbuffer(L, body, body.length, toLua(name)) !== lua.LUA_OK) {
    throw new Error(fengari.to_jsstring(lua.lua_tostring(L, -1)));
  }
  if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    throw new Error(fengari.to_jsstring(lua.lua_tostring(L, -1)));
  }
}

loadChunk("prelude", prelude);
loadChunk("@tests/ready-turnins.test.lua", source);
