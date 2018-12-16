#include <sourcemod>
#include <system2>

#pragma semicolon 1
#pragma newdecls required

#define PDAYS 30

public Plugin myinfo = 
{
	name = "VPN Block",
	author = "PwnK",
	description = "Blocks VPNs",
	version = "1.0.1",
	url = "https://pelikriisi.fi/"
};

Handle db;
bool g_written = false;

public void OnPluginStart()
{
	LoadTranslations ("vpnblock.phrases");
	if (!SQL_CheckConfig("VPNBlock"))
	{
		SQL_TConnect(OnSqlConnect, "default");
		return;
	}
	SQL_TConnect(OnSqlConnect, "VPNBlock");
}

public void OnSqlConnect(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		SetFailState("Databases don't work");
	}
	else
	{
		db = hndl;
		char buffer[255];
		Format(buffer, sizeof(buffer), "CREATE TABLE IF NOT EXISTS `VPNBlock` (`playername` char(128) NOT NULL, `steamid` char(32) NOT NULL, `lastupdated` int(64) NOT NULL, `ip` char(32) NOT NULL, `proxy` boolean NOT NULL, PRIMARY KEY (`ip`))");
		SQL_TQuery(db, queryC, buffer);
	}
}

public void queryC(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		VPNBlock_Log(2, _, _, error);
		return;
	}
	PruneDatabase();
}

public void OnMapStart()
{
	g_written = false;
}

public void OnClientAuthorized(int client, const char[] auth)
{
	if (!IsFakeClient(client))
	{
		char ip[30];
		GetClientIP(client, ip, sizeof(ip));
		char buffer[255];
		Format(buffer, sizeof(buffer), "SELECT proxy FROM VPNBlock WHERE ip = '%s'", ip);
		
		DBResultSet query = SQL_Query(db, buffer);
		if (query == null)
		{
			char error[255];
			SQL_GetError(db, error, sizeof(error));
			VPNBlock_Log(2, _, _, error);
			OnPluginStart();
			return;
		}
		
		if(!SQL_FetchRow(query))
		{
			CheckIpHttp(ip, client);
			return;
		}
		
		if (SQL_FetchInt(query, 0) == 1)
		{
			VPNBlock_Log(0, client, ip);
			KickClient(client, "%t", "VPN Kick");
		}
	}
}

void CheckIpHttp(char[] ip, int client)
{
	DataPack pack = new DataPack();
	pack.WriteString(ip);
	pack.WriteCell(client);
	char url[85];
	Format(url, sizeof(url), "http://proxy.mind-media.com/block/proxycheck.php?ip=%s", ip);
	System2HTTPRequest CheckIp = new System2HTTPRequest(HttpResponseCallback, url);
	CheckIp.Any = pack;
	CheckIp.Timeout = 5;
	CheckIp.GET();
	delete CheckIp;
}

void HttpResponseCallback(bool success, const char[] error, System2HTTPRequest request, System2HTTPResponse response, HTTPRequestMethod method)
{
	if(success)
	{
		char[] content = new char[response.ContentLength + 1];
		response.GetContent(content, response.ContentLength + 1);
		char steamid[28];
		char name[100];
		char ip[30];
		DataPack pack = request.Any;
		pack.Reset();
		pack.ReadString(ip, sizeof(ip));
		int client = pack.ReadCell();
		delete pack;
		GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
		GetClientName(client, name, sizeof(name));
		
		if (StrEqual(content, "Y"))
		{
			VPNBlock_Log(0, client, ip);
			KickClient(client, "%t", "VPN Kick");
			char query[300];
			Format(query, sizeof(query), "INSERT INTO VPNBlock(playername, steamid, lastupdated, ip, proxy) VALUES('%s', '%s', '%d', '%s', '1');", name, steamid, GetTime(), ip);
			SQL_TQuery(db, queryI, query);
		}
		else
		{
			char query[300];
			Format(query, sizeof(query), "INSERT INTO VPNBlock(playername, steamid, lastupdated, ip, proxy) VALUES('%s', '%s', '%d', '%s', '0');", name, steamid, GetTime(), ip);
			SQL_TQuery(db, queryI, query);
		}
	}
	else
	{
		if (!g_written)
		{
			g_written = true;
			VPNBlock_Log(1);
		}
	}
}

public void queryI(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		VPNBlock_Log(2, _, _, error);
		OnPluginStart();
	}
}

void PruneDatabase()
{
	int maxlastupdated = GetTime() - (PDAYS * 86400);
	char buffer[255];
	Format(buffer, sizeof(buffer), "DELETE FROM VPNBlock WHERE lastupdated<'%d';", maxlastupdated);
	SQL_TQuery(db, queryP, buffer);
}

public void queryP(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		VPNBlock_Log(2, _, _, error);
	}
}

void VPNBlock_Log(int logtype, int client = 0, char[] ip = "", const char[] error = "")
{
	char date[32];
	FormatTime(date, sizeof(date), "%d/%m/%Y %H:%M:%S", GetTime());
	char LogPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, LogPath, sizeof(LogPath), "logs/VPNBlock_Log.txt");
	Handle logFile = OpenFile(LogPath, "a");
	if (logtype == 0)
	{
		char steamid[28];
		char name[100];
		GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
		GetClientName(client, name, sizeof(name));
		WriteFileLine(logFile, "[VPNBlock] %T", "Log VPN Kick", LANG_SERVER, date, name, steamid, ip);
	}
	else if (logtype == 1)
	{
		WriteFileLine(logFile, "[VPNBlock] %T", "Http Error", LANG_SERVER, date);
	}
	else
	{
		WriteFileLine(logFile, "[VPNBlock] %T", "Query Failure", LANG_SERVER, date, error);
	}
	delete logFile;
}