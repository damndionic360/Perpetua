-- Forums in game: a read-only snapshot of the site's forums. An officer's Perpetua app writes it into
-- SiteData.lua (PerpetuaSiteForums), and the addon passes it around the guild as part "F" of guild sync, like
-- the raid calendar: only an officer's copy is accepted. It holds the boards every guild member may read on the
-- site (never officer-only ones), the most recently active threads and their latest posts as plain text.
-- Replying happens on the site.
local _, ns = ...

local function store()
  local g = PerpetuaDB.guilds and PerpetuaDB.guilds[ns.guildName() or "No guild"]
  if not g then ns.players(); g = PerpetuaDB.guilds[ns.guildName() or "No guild"] end
  return g
end

-- { t, boards = { { id, n, s } }, threads = { { id, b, title, by, pin, lock, n, last, posts = { { id, by, r, t, body, cut } } } } }
function ns.forums() return ns.FORUMS and store().forums or nil end

function ns.forumsVersion()
  local f = ns.forums()
  return f and f.t and tostring(f.t) or nil
end

function ns.adoptForums(f)
  if not ns.FORUMS then return false end
  if type(f) ~= "table" or not tonumber(f.t) or type(f.threads) ~= "table" or type(f.boards) ~= "table" then return false end
  local cur = ns.forums()
  if cur and (cur.t or 0) >= f.t then return false end
  store().forums = f
  ns.fire()
  return true
end

function ns.loadSiteForums()
  if PerpetuaSiteForums and ns.adoptForums(PerpetuaSiteForums) then ns.announce() end
end

-- Read markers: the newest post id seen in each thread (account-wide).
function ns.threadUnread(t)
  local last = t.posts and t.posts[#t.posts]
  local seen = PerpetuaDB.forumRead and PerpetuaDB.forumRead[tostring(t.id)]
  return last and (not seen or seen < last.id) or false
end

function ns.markThreadRead(t)
  local last = t.posts and t.posts[#t.posts]
  if not last then return end
  PerpetuaDB.forumRead = PerpetuaDB.forumRead or {}
  PerpetuaDB.forumRead[tostring(t.id)] = last.id
end
