#include <prof>
#include <regex>

#define NICKNAME_COUNT 64
#define DEFAULT_NULL_NICKNAME "undefiend"

char buff[256];
char buffer2[256];

ArrayList g_hReplaceKeys;

void RetrunValues()
{
	strcopy(buff, sizeof(buff), "Hello world world worldworldworld world world!");
	strcopy(buffer2, sizeof(buffer2), "Hello world world worldworldworld world world!");
}

public void OnPluginStart()
{
	RetrunValues();
	
	g_hReplaceKeys = new ArrayList(ByteCountToCells(NICKNAME_COUNT));

	WithValues();
	//WithOutValues();

	//_Regex();
	//_One();

	
	Prof_Start(100);
	Prof_Test("_Regex");
	Prof_Test("_One");
	Prof_Results();
	

	SetFailState("OK");
}

public void WithValues()
{
	PrintToServer("TEST WITH KEYS");
	g_hReplaceKeys.PushString("world");
	g_hReplaceKeys.PushString("Domikuss");
}

public void WithOutValues()
{
	PrintToServer("TEST WITHOUT KEYS");
	g_hReplaceKeys.PushString("hi");
	g_hReplaceKeys.PushString("Domikuss");
}

public int _Regex()
{
	char sKey[NICKNAME_COUNT], szBuffer[2][NICKNAME_COUNT];	

	int iCountKeys;

	for(int i = 0, iSize = g_hReplaceKeys.Length, iLen, iEnd, iStart; i < iSize; i++)
	{
		g_hReplaceKeys.GetString(i, sKey, sizeof(sKey));

		Regex regex = CompileRegex(sKey, PCRE_MULTILINE);
		if(regex == INVALID_HANDLE) continue;
		iLen = strlen(sKey);
		regex.Match(buffer2);
		while( regex.MatchCount() > 0)
		{
			iEnd = regex.MatchOffset(0);
			iStart = iEnd - iLen;
			iEnd -= 1;
			//char byf[256];
			//strcopy(byf, iLen+1, buffer2[iStart]);
			//PrintToServer("Finded key: %s (Start: %i, iEnd: %i)", byf, iStart, iEnd);
			strcopy(szBuffer[1], sizeof(szBuffer[]), buffer2[iEnd+1]);
			buffer2[iStart] = EOS;
			FormatEx(szBuffer[0], sizeof(szBuffer[]), "%s%s", buffer2, szBuffer[1]);
			strcopy( buffer2, sizeof(buffer2), szBuffer[0]);
			regex.Match(buffer2);

			iCountKeys++;
		}
	}

	TrimString(buffer2);

	if(!strcmp(buffer2, ""))
	{
		strcopy(buffer2, sizeof(buffer2), DEFAULT_NULL_NICKNAME);
	}

	//PrintToServer("ИТОГ _Regex: %s, Найдено ключей: %i", buffer2, iCountKeys);

	RetrunValues();

	return iCountKeys++;
}

public int _One()
{
	int iCountKeys = 0;
	char sKey[NICKNAME_COUNT], szBuffer[2][NICKNAME_COUNT];

	for(int i = 0, iSize = g_hReplaceKeys.Length, iLen, iPos; i < iSize; i++)
	{
		g_hReplaceKeys.GetString(i, sKey, sizeof(sKey));
		iLen = strlen(sKey);

		iPos = StrContains(buff, sKey, false);
		if(iPos != -1)
		{
			strcopy(szBuffer[1], sizeof(szBuffer[]), buff[iPos + iLen]);
			buff[iPos] = EOS;
			FormatEx(szBuffer[0], sizeof(szBuffer[]), "%s%s", buff, szBuffer[1]);
			strcopy( buff, sizeof(buff), szBuffer[0]);
			iCountKeys++;
		}
	}

	TrimString(buff);

	if(!strcmp(buff, ""))
	{
		strcopy(buff, sizeof(buff), DEFAULT_NULL_NICKNAME);
	}
	
	// Если было найдены ключ и из-за смещения ключ был не определён.
	if(iCountKeys > 0)
	{
		iCountKeys += _One();
	}

	//PrintToServer("ИТОГ _One: %s, Найдено ключей: %i", buff, iCountKeys);

	RetrunValues();

	return iCountKeys;
}