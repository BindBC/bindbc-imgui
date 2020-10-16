import std.stdio;
import std.file;
import std.json;
import std.array;
import std.format;
import std.string;
import std.algorithm;
import std.algorithm.searching;
import std.algorithm.iteration;

shared immutable string[string] cArgMap;
shared immutable string[string] cTypeMap;

shared static this()
{
    cArgMap = [
        "align": "alignment",
        "ref" : "reference",
        "in" : "inItem",
        "out" : "outItem"
    ];
    
    cTypeMap = [
        "unsigned char": "char",
        "unsigned_char": "char",
        "unsigned short": "ushort",
        "unsigned int": "uint",
        "unsigned char*": "char*",
        "unsigned short*": "ushort*",
        "unsigned int*": "uint*",
        "signed char": "byte",
        "signed short": "short",
        "signed int": "int",
        "signed char*": "byte*",
        "signed short*": "short*",
        "signed int*": "int*",
        "int64_t" : "long",
        "uint64_t" : "ulong",
        "union { int BackupInt[2]; float BackupFloat[2];}": "union { int[2] BackupInt; float[2] BackupFloat;}",
        "const char* const[]" : "const(char)**",
        "unsigned char[256]" : "char[256]",
        "unsigned char**" : "char**",
        "const unsigned char[256]" : "const char[256]"
    ];
}

string imgui_argname_to_dlang(string imguiName)
{
    if (auto type = imguiName in cArgMap)
    {
        return *type;
    }

    return imguiName;
}

string imgui_type_to_dlang(string imguiType)
{
    if (auto type = imguiType in cTypeMap)
    {
        return *type;
    }

    imguiType = imguiType.replace("struct ", "");
    imguiType = imguiType.replace("(*)", " function");

    return imguiType;
}

string loaderPrelude = `
module bindbc.imgui.dynload;

version(BindImGui_Static) {}
else:

import bindbc.loader;
import bindbc.imgui.config,
       bindbc.imgui.bind,
       bindbc.imgui.bind.imgui;

private {
    SharedLib lib;
    ImGuiSupport loadedVersion;
}

void unloadImGui()
{
    if(lib != invalidHandle) {
        lib.unload();
    }
}

ImGuiSupport loadedImGuiVersion() { return loadedVersion; }

bool isImGuiLoaded()
{
    return  lib != invalidHandle;
}

ImGuiSupport loadImGui()
{
    // #1778 prevents me from using static arrays here :(
    version(Windows) {
        const(char)[][3] libNames = [
            "cimgui.dll",
            "cimgui.dll",
            "cimgui.dll"
        ];
    }
    else version(OSX) {
        const(char)[][6] libNames = [
            "cimgui.dylib"
        ];
    }
    else version(Posix) {
        const(char)[][2] libNames = [
            "cimgui.so"
        ];
    }
    else static assert(0, "bindbc-ImGui is not yet supported on this platform.");

    ImGuiSupport ret;
    foreach(name; libNames) {
        ret = loadImGui(name.ptr);
        if(ret != ImGuiSupport.noLibrary) break;
    }
    return ret;
}

ImGuiSupport loadImGui(const(char)* libName)
{
    lib = load(libName);
    if(lib == invalidHandle) {
        return ImGuiSupport.noLibrary;
    }

    auto errCount = errorCount();
    loadedVersion = ImGuiSupport.badLibrary;
`;

string loaderEnd = `

    return loadedVersion;
}
`;

const string imPool = `

struct TypeToReplace 
{
    TemplatedTypeToReplace Buf;
    ImGuiStorage Map;
    ImPoolIdx FreeIdx;
}

`;


const string imVector = `
struct TypeToReplace
{
    int Size;
    int Capacity;
    TemplatedTypeToReplace* Data;
}

`;

const string imChunkStream = `
struct TypeToReplace 
{
    TemplatedTypeToReplace Buf;
}

`;

const string baseImVector = `
struct ImVector
{
    int Size;
    int Capacity;
    void* Data;
}

`;


string get_imvector_structs(Appender!string strBuilder, JSONValue definitions)
{
    string[string] imTemplateTypes;
    auto structs = definitions["structs"];
    foreach (string structName, JSONValue structMembers; structs) 
    {
        foreach (JSONValue value; structMembers.array)
        {
            //string typeName = imgui_type_to_dlang(value["type"].str);
            //string objectName = value["name"].str;
            //if (startsWith(typeName, "ImVector_"))
            //{
            //    ++imTemplateTypes.length;
            //    imTemplateTypes[imTemplateTypes.length - 1] = imgui_type_to_dlang(typeName["ImVector_".length .. typeName.length]);
            //}

            if ("template_type" in value)
                imTemplateTypes[value["type"].str] =  value["template_type"].str;
        }
    }

    strBuilder.put(baseImVector);

    foreach (string templateName, string templatedOnType; imTemplateTypes)
    {
        string structTemplate;
        if (startsWith(templateName, "ImVector_"))
            structTemplate = imVector;
        else if (startsWith(templateName, "ImPool_"))
            structTemplate = imPool;
        else if (startsWith(templateName, "ImChunkStream_"))
            structTemplate = imChunkStream;

        strBuilder.put(structTemplate.replace("TemplatedTypeToReplace", imgui_type_to_dlang(templatedOnType)).replace("TypeToReplace", templateName));
    }

    return strBuilder.data;
}

string get_typedefs(Appender!string strBuilder, JSONValue typedefs)
{
    foreach (string typedefName, JSONValue typeDefValue; typedefs) 
    {
        const string originalTypeName = imgui_type_to_dlang(typeDefValue.str);

        if (originalTypeName == "T") continue;
        if (typedefName == "iterator") continue;
        if (typedefName == "const_iterator") continue;

        if (originalTypeName != typedefName)
            strBuilder.put(format("alias %s = %s;\n", typedefName,originalTypeName));
    }

    return strBuilder.data;
}

string get_enums(Appender!string strBuilder, JSONValue definitions)
{
    auto enums = definitions["enums"];
    foreach (string enumName, JSONValue enumValues; enums) 
    {
        string adjustedName = enumName;

        if ('_' == adjustedName[adjustedName.length - 1])
            adjustedName = adjustedName[0 .. adjustedName.length - 1];

        strBuilder.put(format("alias %s = int;\n", enumName));
        strBuilder.put("enum {\n");

        foreach (JSONValue value; enumValues.array)
            strBuilder.put(format("    %s = %d,\n", value["name"].str, value["calc_value"].integer));

        strBuilder.put("}\n\n");
    }

    return strBuilder.data;
}

string get_structs(Appender!string strBuilder, JSONValue definitions)
{
    auto structs = definitions["structs"];
    foreach (string structName, JSONValue structMembers; structs) 
    {
        strBuilder.put(format("struct %s {\n", structName));

        foreach (JSONValue value; structMembers.array)
        {
            string typeName = imgui_type_to_dlang(value["type"].str);
            string objectName = value["name"].str;

            if ((0 != objectName.length) && (']' == objectName[objectName.length - 1]))
            {
                ptrdiff_t position = std.string.lastIndexOf(objectName, '[');
                typeName = typeName ~ objectName[position .. objectName.length];
                objectName = objectName[0 .. position];
            }
            else
            {

            }

            strBuilder.put(format("    %s %s;\n", typeName, objectName));
        }

        strBuilder.put("}\n\n");
    }

    return strBuilder.data;
}


string write_function_loading(Appender!string strBuilder, JSONValue definitions)
{
    foreach (string functionName, JSONValue functionDecl; definitions) 
    {
        foreach (JSONValue cimguiFunction; functionDecl.array)
        {
            if ("templated" in cimguiFunction && cimguiFunction["templated"].boolean)
                continue;
                
            strBuilder.put(format("    lib.bindSymbol(cast(void**)&%s, \"%s\");\n", cimguiFunction["ov_cimguiname"].str, cimguiFunction["ov_cimguiname"].str));
        }
    }

    return strBuilder.data;
}

string get_functions(Appender!string strBuilder, JSONValue definitions, bool functionDecls)
{    
    string[] imFunctionPtrTypes;

    strBuilder.put("extern(C) @nogc nothrow {\n");
    foreach (string functionName, JSONValue functionDecl; definitions)
    {
        if (functionName == "ImVector_ImVector")
            continue;

        foreach (JSONValue cimguiFunction; functionDecl.array)
        {
            string returnType;

            if ("templated" in cimguiFunction && cimguiFunction["templated"].boolean)
                continue;

            if ("constructor" in cimguiFunction && cimguiFunction["constructor"].boolean)
                returnType = format("%s*", functionName[0 .. std.string.lastIndexOf(functionName, '_')]);
            else
                returnType = cimguiFunction["ret"].str;


            if (!functionDecls)
            {
                string functionPtrType = "p" ~ cimguiFunction["ov_cimguiname"].str;
                ++imFunctionPtrTypes.length;
                imFunctionPtrTypes[imFunctionPtrTypes.length - 1] = functionPtrType;
                strBuilder.put("alias " ~ functionPtrType ~ " = ");
            }

            strBuilder.put(imgui_type_to_dlang(returnType));
            strBuilder.put(' ');
            
            if (functionDecls)
                strBuilder.put(cimguiFunction["ov_cimguiname"].str);
            else
                strBuilder.put("function");
            
            strBuilder.put("(");

            int i = 0;
            foreach (JSONValue parameter; cimguiFunction["argsT"].array)
            {
                string argType = imgui_type_to_dlang(parameter["type"].str);
                string argName = parameter["name"].str;

                // Deal with arraySubScriptToken in Arg name
                if ((0 != argName.length) && (']' == argName[argName.length - 1]))
                {
                    ptrdiff_t position = std.string.lastIndexOf(argName, '[');

                    argType = argType ~ argName[position .. argName.length];
                    argName = argName[0 .. position];
                }
                
                // Deal with arraySubScriptToken in Arg Type
                if ((0 != argType.length) && (']' == argType[argType.length - 1]))
                {
                    ptrdiff_t position = std.string.lastIndexOf(argType, '[');

                    const string arraySubScriptToken = argType[position .. argType.length];
                    argType = argType ~ "*";

                    if (arraySubScriptToken != "[]")
                    {
                        argType = argType ~ "/*" ~ arraySubScriptToken ~ "*/";
                    }
                }

                argName = imgui_argname_to_dlang(argName);

                strBuilder.put(imgui_type_to_dlang(argType));
                strBuilder.put(' ');

                // Don't write the name out if this function is variadic
                if (argName != "...") strBuilder.put(argName);

                if (++i != cimguiFunction["argsT"].array.length) strBuilder.put(", ");
            }
            
            strBuilder.put(");\n");
        }
    }

    
    if (!functionDecls)
    {
        strBuilder.put("__gshared {\n");
        
        foreach (string item; imFunctionPtrTypes)
        {
            strBuilder.put(item ~ " " ~ item[1 .. item.length] ~ ";\n");
        }

        strBuilder.put("}\n");
    }

    
    strBuilder.put("}\n");

    return strBuilder.data;
}

void write_imgui_file(
    JSONValue typedefs_dict,
    JSONValue structs_and_enums,
    JSONValue definitions,
    JSONValue impl_definitions)
{
    auto strBuilder = appender!string;

    strBuilder.put("module bindbc.imgui.bind.imgui;\n\n");
    strBuilder.put("import core.stdc.stdio;\n\n");
    strBuilder.put("import core.stdc.stdarg;\n\n");
    strBuilder.put("import bindbc.sdl;\n\n");
    strBuilder.put("import bindbc.glfw;\n\n");

    get_typedefs(strBuilder, typedefs_dict);
    strBuilder.put("\n\n");
    get_imvector_structs(strBuilder, structs_and_enums);
    strBuilder.put("\n\n");
    get_enums(strBuilder, structs_and_enums);
    strBuilder.put("\n\n");
    get_structs(strBuilder, structs_and_enums);
    strBuilder.put("\n\n");

    strBuilder.put("version(BindImGui_Static) {\n");

    get_functions(strBuilder, definitions, true);
    get_functions(strBuilder, impl_definitions, true);
    
    strBuilder.put("}\n");

    strBuilder.put("else {\n");

    get_functions(strBuilder, definitions, false);
    get_functions(strBuilder, impl_definitions, false);
    
    strBuilder.put("}\n");
    

    

    std.file.write("source/bindbc/imgui/bind/imgui.d", strBuilder.data);
}

void write_loader(
    JSONValue definitions,
    JSONValue impl_definitions)
{
    auto strBuilder = appender!string;
    strBuilder.put(loaderPrelude);
    strBuilder.put("\n");

    write_function_loading(strBuilder, definitions);

    strBuilder.put("\n\n");
    strBuilder.put("// Backends\n");

    write_function_loading(strBuilder, impl_definitions);

    strBuilder.put(loaderEnd);
    
    std.file.write("source/bindbc/imgui/dynload.d", strBuilder.data);
}

void main()
{
    JSONValue typedefs_dict = parseJSON(std.file.readText("./cimgui/generator/output/typedefs_dict.json"));
    JSONValue structs_and_enums = parseJSON(std.file.readText("./cimgui/generator/output/structs_and_enums.json"));
    JSONValue definitions = parseJSON(std.file.readText("./cimgui/generator/output/definitions.json"));
    JSONValue impl_definitions = parseJSON(std.file.readText("./cimgui/generator/output/impl_definitions.json"));

    write_loader(definitions, impl_definitions);
    write_imgui_file(typedefs_dict, structs_and_enums, definitions, impl_definitions);

    //JSONValue definitions = parseJSON(std.file.readText("./cimgui/generator/output/definitions.json"));
    //JSONValue impl_definitions = parseJSON(std.file.readText("./cimgui/generator/output/impl_definitions.json"));
    //JSONValue typedefs_dict = parseJSON(std.file.readText("./cimgui/generator/output/typedefs_dict.json"));

    //WriteFunctionBindings(definitions);
    //write_function_loading(impl_definitions);
}