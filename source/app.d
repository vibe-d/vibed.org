import vibe.d;

import std.algorithm;
import std.array;
import std.datetime;

version (Have_vibelog) {
	import vibelog.web;
	VibeLogController s_vibelog;
}

string s_latestVersion = "0.8.6"; // updated at run time by searching for download files
URLRouter s_router;

void home(HTTPServerRequest req, HTTPServerResponse res)
{
	version (Have_vibelog) {
		auto info = s_vibelog.getPostListInfo(0, 6);
	} else {
		struct Info {}
		Info info;
	}
	res.render!("home.dt", req, info);
}

void download(HTTPServerRequest req, HTTPServerResponse res)
{
	enum zipball_prefix = "zipball/";

	if (auto pf = "file" in req.query) {
		auto path = InetPath(*pf).bySegment;

		if (path.front.name == "zipball") {
			path.popFront();
			auto fname = path.front.name;
			path.popFront();
			if (!path.empty) return; // only accept paths of length 2
			res.redirect("https://github.com/vibe-d/vibe.d/zipball/" ~ fname);
		} else {
			auto fname = path.front.name;
			path.popFront();
			if (!path.empty) return; // only accept paths of length 1
			res.redirect("https://vibed.org/files/" ~ fname);
		}
	} else res.render!("download.dt", req);
}

void error(HTTPServerRequest req, HTTPServerResponse res, HTTPServerErrorInfo error)
{
	req.params["latestRelease"] = s_latestVersion;
	res.render!("error.dt", req, error);
}

version(Have_ddox)
{
	import ddox.ddox;
	import ddox.entities;
	import ddox.htmlserver;
	import ddox.htmlgenerator;
	import ddox.parsers.jsonparser;

	Package[string] s_rootPackage;
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
				static import vibe.core.core;
				vibe.core.core.yield(); // let the server run in parallel
				string text = readFileUTF8(de.name);
				auto json = parseJson(text);
				auto pack = parseJsonDocs(json);
				auto settings = new DdoxSettings;
				processDocs(pack, settings);
				s_rootPackage[ver] = pack;
				if (ver.length) versions ~= ver;

				auto docsettings = new GeneratorSettings;
				docsettings.navigationType = NavigationType.ModuleTree;
				if (!ver.length) docsettings.siteUrl = URL("https://vibed.org/api");
				else docsettings.siteUrl = URL("https://vibed.org/api-"~ver);
				registerApiDocs(s_router, pack, docsettings);
			} catch( Exception e ){
				logError("Error loading docs: %s", e.toString());
				throw e;
			}
		}
		foreach_reverse (v; versions.sort!("a.length == 0 || a < b"))
			s_docsVersions ~= ";" ~ v;
	}
}

string prettifyFilter(string html)
@safe {
	return html.replace("<pre class=\"prettyprint\">", "<pre class=\"code prettyprint\">");
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

void redirectDlangDocs(HTTPServerRequest req, HTTPServerResponse res)
{
	string path = "index.html";
	static immutable prefixes = [
		"/temp/d-programming-language.org/phobos/",
		"/temp/dlang.org/library/"
	];
	foreach (p; prefixes)
		if (req.path.startsWith(p)) {
			path = req.path[p.length .. $];
			break;
		}
	res.redirect("https://dlang.org/library/"~path, HTTPStatus.movedPermanently);
}

version (unittest) {
	void main() {}
} else:
void main()
{
	//setLogLevel(LogLevel.none);
	setLogFile("log.txt", LogLevel.info);

	auto settings = new HTTPServerSettings;
	settings.hostName = "vibed.org";
	settings.port = 8003;
	settings.bindAddresses = ["127.0.0.1"];
	settings.sessionStore = new MemorySessionStore;
	settings.errorPageHandler = toDelegate(&error);

	s_router = new URLRouter;

	with (s_router) {
		get("*", (req, res) {
			req.params["latestRelease"] = s_latestVersion;
			version(Have_ddox) req.params["docsVersions"] = s_docsVersions;
		});
		get("/",          &home);
		get("/about",     staticTemplate!"about.dt");
		get("/contact",   staticTemplate!"contact.dt");
		get("/community", staticTemplate!"community.dt");
		get("/impressum", staticTemplate!"impressum.dt");
		get("/download",  &download);
		get("/features",  staticTemplate!"features.dt");
		get("/docs",      staticTemplate!"docs.dt");
		get("/developer", staticRedirect("/get-involved"));
		get("/get-involved", staticTemplate!"developer.dt");
		get("/style-guide", staticTemplate!"styleguide.dt");
		get("/templates", staticRedirect("/templates/"));
		get("/templates/", staticRedirect("/templates/diet"));
		get("/templates/diet", staticTemplate!"templates.dt");
		get("/tutorials", staticTemplate!"tutorials.dt");
		get("/temp/d-programming-language.org/*", &redirectDlangDocs);
		get("/temp/dlang.org/*", &redirectDlangDocs);
	}

	auto fsettings = new HTTPFileServerSettings;
	fsettings.maxAge = 0.seconds();
	s_router.get("*", serveStaticFiles("./public/", fsettings));

	version(Have_vibelog)
	{
		auto blogsettings = new VibeLogSettings;
		blogsettings.configName = "vibe.d";
		blogsettings.databaseURL = "mongodb://127.0.0.1/vibelog";
		blogsettings.siteURL = URL("https://vibed.org/blog/");
		blogsettings.textFilters ~= toDelegate(&prettifyFilter);
		blogsettings.showFullPostsInPostList = false;
		blogsettings.postsPerPage = 10;
		blogsettings.maxRecentPosts = 100;
		s_vibelog = new VibeLogController(blogsettings);
		s_router.registerVibeLogWeb(s_vibelog);
	}

	version(Have_ddox)
	{
		runTask(toDelegate(&updateDocs));
	}

	s_router.rebuild(); // avoid delay on first request

	listenHTTP(settings, s_router);

	updateDownloads();
	setTimer(10.seconds(), {updateDownloads();}, true);

	runApplication();
}
