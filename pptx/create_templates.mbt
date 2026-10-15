///|
fn created_pptx_color_map() -> String {
  "<p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/>"
}

///|
fn created_pptx_theme() -> String {
  (
    #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    #|<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="MoonLeaf Research">
    #|<a:themeElements><a:clrScheme name="MoonLeaf">
    #|<a:dk1><a:srgbClr val="152536"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="263445"/></a:dk2><a:lt2><a:srgbClr val="F4F6FA"/></a:lt2>
    #|<a:accent1><a:srgbClr val="5574E8"/></a:accent1><a:accent2><a:srgbClr val="22A78B"/></a:accent2><a:accent3><a:srgbClr val="E8A23B"/></a:accent3><a:accent4><a:srgbClr val="916ACA"/></a:accent4><a:accent5><a:srgbClr val="39A4C4"/></a:accent5><a:accent6><a:srgbClr val="D86573"/></a:accent6><a:hlink><a:srgbClr val="3458D8"/></a:hlink><a:folHlink><a:srgbClr val="7356A8"/></a:folHlink></a:clrScheme>
    #|<a:fontScheme name="MoonLeaf"><a:majorFont><a:latin typeface="Aptos Display"/><a:ea typeface="Microsoft YaHei"/><a:cs typeface="Arial"/><a:font script="Hans" typeface="Microsoft YaHei"/><a:font script="Hant" typeface="Microsoft JhengHei"/></a:majorFont><a:minorFont><a:latin typeface="Aptos"/><a:ea typeface="Microsoft YaHei"/><a:cs typeface="Arial"/><a:font script="Hans" typeface="Microsoft YaHei"/><a:font script="Hant" typeface="Microsoft JhengHei"/></a:minorFont></a:fontScheme>
    #|<a:fmtScheme name="MoonLeaf"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"><a:tint val="50000"/></a:schemeClr></a:solidFill><a:solidFill><a:schemeClr val="phClr"><a:shade val="50000"/></a:schemeClr></a:solidFill></a:fillStyleLst>
    #|<a:lnStyleLst><a:ln w="6350" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/><a:miter lim="800000"/></a:ln><a:ln w="12700" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/><a:miter lim="800000"/></a:ln><a:ln w="19050" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/><a:miter lim="800000"/></a:ln></a:lnStyleLst>
    #|<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"><a:tint val="95000"/></a:schemeClr></a:solidFill><a:solidFill><a:schemeClr val="phClr"><a:shade val="95000"/></a:schemeClr></a:solidFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements>
    #|<a:objectDefaults/><a:extraClrSchemeLst/></a:theme>
  )
}

///|
fn created_pptx_master() -> String {
  "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:sldMaster xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"><p:cSld name=\"MoonLeaf Research\"><p:bg><p:bgPr><a:solidFill><a:srgbClr val=\"FFFFFF\"/></a:solidFill><a:effectLst/></p:bgPr></p:bg><p:spTree>\{created_pptx_group()}</p:spTree></p:cSld>\{created_pptx_color_map()}<p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"rIdLayout\"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle><a:lvl1pPr><a:defRPr sz=\"3200\" b=\"1\"/></a:lvl1pPr></p:titleStyle><p:bodyStyle><a:lvl1pPr marL=\"285750\" indent=\"-228600\"><a:buChar char=\"•\"/><a:defRPr sz=\"2200\"/></a:lvl1pPr></p:bodyStyle><p:otherStyle><a:defPPr><a:defRPr sz=\"1800\"/></a:defPPr></p:otherStyle></p:txStyles></p:sldMaster>"
}

///|
fn created_pptx_layout() -> String {
  "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:sldLayout xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" type=\"blank\" preserve=\"1\"><p:cSld name=\"MoonLeaf Editable Text\"><p:spTree>\{created_pptx_group()}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>"
}

///|
fn created_pptx_notes_master() -> String {
  let body = created_pptx_shape(
    2,
    "Notes body",
    685800,
    3886200,
    5486400,
    4800600,
    "<a:p><a:endParaRPr lang=\"zh-CN\" sz=\"1200\"/></a:p>",
    placeholder="<p:ph type=\"body\" idx=\"1\"/>",
  )
  "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:notesMaster xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"><p:cSld><p:spTree>\{created_pptx_group()}\{body}</p:spTree></p:cSld>\{created_pptx_color_map()}<p:notesStyle><a:lvl1pPr><a:defRPr sz=\"1200\"/></a:lvl1pPr></p:notesStyle></p:notesMaster>"
}
