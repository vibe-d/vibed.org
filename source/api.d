module api;

import std.array;
import std.format;
import std.string;
import vibe.core.log;
import vibe.data.json;


string getFunctionName(Json proto)
{
	auto n = proto.name.get!string;
	if( auto ptn = "templateName" in proto ){
		auto tn = ptn.get!string;
		if( tn.startsWith(n~"(") )
			return tn;
		return tn ~ "." ~ n;
	}
	return n;
}

string formatType()(Json type)
{
	logInfo("format type: %s", type);
	auto ret = appender!string();
	formatType(ret, type);
	return ret.data();
}

void formatType(R)(ref R dst, Json type)
{
	auto attribs = type.attributes.opt!(Json[]);
	switch( type.typeClass.get!string ){
		default:
		case "primitive":
			if( type.moduleName.length ){
				auto mn = type.moduleName.get!string;
				auto qn = type.qualifiedName.get!string;
				if( qn.startsWith(mn~".") ) qn = qn[mn.length+1 .. $];
				formattedWrite(dst, "<a href=\"../%s/%s\">%s</a>", mn, qn, qn);
			} else {
				dst.put(type.name.get!string);
			}
			break;
		case "function":
		case "delegate":
			formatType(dst, type.returnType);
			dst.put('(');
			foreach( size_t i, p; type.parameters ){
				if( i > 0 ) dst.put(", ");
				formatType(dst, p["type"]);
				if( "name" in p ){
					dst.put(' ');
					dst.put(p.name.get!string);
				}
			}
			dst.put(')');
			foreach( att; attribs )
				dst.put(att.get!string());
			break;
		case "pointer":
			foreach( att; attribs ){
				dst.put(att.get!string);
				dst.put('(');
			}
			formatType(dst, type.elementType);
			dst.put('*');
			foreach( att; attribs ) dst.put(')');
			break;
		case "array":
			foreach( att; attribs ){
				dst.put(att.get!string);
				dst.put('(');
			}
			formatType(dst, type.elementType);
			dst.put("[]");
			foreach( att; attribs ) dst.put(')');
			break;
		case "static array":
			foreach( att; attribs ){
				dst.put(att.get!string);
				dst.put('(');
			}
			formatType(dst, type.elementType);
			formattedWrite(dst, "[%s]", type.elementCount);
			foreach( att; attribs ) dst.put(')');
			break;
		case "associative array":
			foreach( att; attribs ){
				dst.put(att.get!string);
				dst.put('(');
			}
			formatType(dst, type.elementType);
			dst.put('[');
			formatType(dst, type.keyType);
			dst.put(']');
			foreach( att; attribs ) dst.put(')');
			break;
	}
}