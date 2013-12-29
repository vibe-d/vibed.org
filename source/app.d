import vibe.d;

import std.algorithm;
import std.array;
import std.datetime;

version(Have_vibelog) import vibelog.vibelog;

string s_latestVersion = "0.7.13";

void download(HTTPServerRequest req, HTTPServerResponse res)
{
	if( auto pf = "file" in req.query ){
		if( (*pf).startsWith("zipball") ) res.redirect("https://github.com/rejectedsoftware/vibe.d/" ~ *pf);
		else res.redirect("http://vibed.org/files/" ~ *pf);
	} else res.renderCompat!("download.dt", HTTPServerRequest, "req")(req);
}

void error(HTTPServerRequest req, HTTPServerResponse res, HTTPServerErrorInfo error)
{
	res.renderCompat!("error.dt",
		HTTPServerRequest, "req",
		HTTPServerErrorInfo, "error")
		(req, error);
}

version(Have_ddox)
{
	import ddox.ddox;
	import ddox.entities;
	import ddox.htmlserver;
	import ddox.htmlgenerator;
	import ddox.jsonparser;

	Package[string] m_rootPackage;
	string s_docsVersions;

	void updateDocs()
	{
		import std.file;
		s_docsVersions = null;
		string[] versions;
		foreach (de; dirEntries(".", "docs*.json", SpanMode.shallow)) {
			auto name = de.name;
			if (name.startsWith("./") || name.startsWith(".\\")) name = name[2 .. $];
			logInfo("DE %s", name);
			assert(name.startsWith("docs") && name.endsWith(".json"));
			auto ver = name[4 .. $-5];
			if (ver.startsWith("-")) ver = ver[1 .. $];
			try {
				import std.file;
				string text = readText(de.name);
				auto json = parseJson(text);
				auto pack = parseJsonDocs(json);
				auto settings = new DdoxSettings;
				processDocs(pack, settings);
				m_rootPackage[ver] = pack;
				if (ver.length) versions ~= ver;
			} catch( Exception e ){
				logError("Error loading docs: %s", e.toString());
				throw e;
			}
		}
		foreach_reverse (v; versions) s_docsVersions ~= ";" ~ v;
	}
}

string prettifyFilter(string html)
{
	return html.replace("<code><pre>", "<code><pre class=\"prettyprint\">");
}

void updateDownloads()
{
	import std.path;
	auto lver = s_latestVersion.split(".").map!(v => v.to!int())().array();

	foreach(de; iterateDirectory("public/files")){
		auto basename = stripExtension(de.name);
		auto parts = basename.split("-");
		if( parts.length != 2 || parts[0] != "vibed" )
			continue;
		auto ver = parts[1].split(".").map!(v => v.to!int())().array();
		if( ver > lver ){
			lver = ver;
			s_latestVersion = parts[1];
		}
	}
}

shared static this()
{
	//setLogLevel(LogLevel.none);
	setLogFile("log.txt", LogLevel.info);

	auto settings = new HTTPServerSettings;
	settings.hostName = "vibed.org";
	settings.port = 8003;
	settings.bindAddresses = ["127.0.0.1"];
	settings.errorPageHandler = toDelegate(&error);
	
	auto router = new URLRouter;
	
	router.get("*", (req, res) {
		req.params["latestRelease"] = s_latestVersion;
		version(Have_ddox) req.params["docsVersions"] = s_docsVersions;
	});
	router.get("/",          staticTemplate!"home.dt");
	router.get("/about",     staticTemplate!"about.dt");
	router.get("/contact",   staticTemplate!"contact.dt");
	router.get("/community", staticTemplate!"community.dt");
	router.get("/impressum", staticTemplate!"impressum.dt");
	router.get("/download",  &download);
	router.get("/features",  staticTemplate!"features.dt");
	router.get("/docs",      staticTemplate!"docs.dt");
	router.get("/developer", staticTemplate!"developer.dt");
	router.get("/style-guide", staticTemplate!"styleguide.dt");
	router.get("/templates", staticRedirect("/templates/"));
	router.get("/templates/", staticRedirect("/templates/diet"));
	router.get("/templates/diet", staticTemplate!"templates.dt");

	auto fsettings = new HTTPFileServerSettings;
	fsettings.maxAge = 0.seconds();
	router.get("*", serveStaticFiles("./public/", fsettings));

	version(Have_vibelog)
	{
		auto blogsettings = new VibeLogSettings;
		blogsettings.configName = "vibe.d";
		blogsettings.siteUrl = URL("http://vibed.org/blog/");
		blogsettings.textFilters ~= &prettifyFilter;
		registerVibeLog(blogsettings, router);
	}

	version(Have_ddox)
	{
		updateDocs();
		auto docsettings = new GeneratorSettings;
		docsettings.navigationType = NavigationType.ModuleTree;
		docsettings.siteUrl = URL("http://vibed.org/api");
		registerApiDocs(router, m_rootPackage[""], docsettings);
		foreach (ver, pack; m_rootPackage) {
			auto docsettings = new GeneratorSettings;
			docsettings.navigationType = NavigationType.ModuleTree;
			docsettings.siteUrl = URL("http://vibed.org/api");
			if (!ver.length) docsettings.siteUrl = URL("http://vibed.org/api");
			else docsettings.siteUrl = URL("http://vibed.org/api-"~ver);
			registerApiDocs(router, pack, docsettings);
		}
	}

	listenHTTP(settings, router);

	updateDownloads();
	setTimer(10.seconds(), {updateDownloads();}, true);
}
