/*
================================================================================
Script Name: Iconia_SaveArchiveSelection
Category: Iconia
Description: Sauvegarde la sélection dans le dossier 1_Archive du projet avec 
             une capture d'écran.             
================================================================================
*/
macroScript Iconia_SaveArchiveSelection
category:"Iconia"
buttonText:"Archive selection"
tooltip:"Save selection in 1_Archive with timestamp and preview"
(
    -- =============================================
    -- HELPER FUNCTIONS
    -- =============================================

    -- Strips known date prefixes (YY_ or YYYY_) from filename
    fn stripDatePrefix fname = (
        local c2 = substring fname 1 2
        local c4 = substring fname 1 4
        local validYY  = #("22","23","24","25","26")
        local validYYYY = #("2022","2023","2024","2025","2026")

        if (findItem validYYYY c4 > 0) and (substring fname 9 1 == "_") then
            return (substring fname 9 fname.count)  -- strip "2026MMDD_"

        if (findItem validYY c2 > 0) and (substring fname 7 1 == "_") then
            return (substring fname 7 fname.count)  -- strip "YYMMDD_"

        return fname  -- no prefix found
    )

    -- Returns a timestamp string: YYYYMMDDHHmm
    fn getTimestamp = (
        local d = getLocalTime()
        local yyyy = d[1] as string
        local mm   = if d[2] < 10 then ("0" + d[2] as string) else (d[2] as string)
        local dd   = if d[4] < 10 then ("0" + d[4] as string) else (d[4] as string)
        local hh   = if d[5] < 10 then ("0" + d[5] as string) else (d[5] as string)
        local mn   = if d[6] < 10 then ("0" + d[6] as string) else (d[6] as string)
        return (yyyy + mm + dd + hh + mn)
    )

    -- Removes illegal Windows filename characters
    fn sanitizeFilename str = (
        local illegal = #("\\", "/", ":", "*", "?", "\"", "<", ">", "|")
        local result = str
        for c in illegal do result = substituteString result c ""
        return result
    )

    -- =============================================
    -- ENTRY POINT
    -- =============================================

    if selection.count == 0 then (
        messageBox "Nothing selected!" title:"Iconia Archive"
        return false
    )

    local selectedObjects = selection as array
    local archiveDir      = maxFilePath + "1_Archive\\"
    local cleanName       = stripDatePrefix maxFileName
    local timestamp       = getTimestamp()
    local baseName        = substituteString (timestamp + cleanName) ".max" "_"
    local archiveBasePath = archiveDir + baseName

    -- Build the suggested name from first selected object
    local suggestedName = try (
        selectedObjects[1].layer.name + "_" + selectedObjects[1].name
    ) catch (
        selectedObjects[1].name
    )

    -- Ensure archive folder exists
    HiddenDosCommand ("mkdir \"" + archiveDir + "\" 2>nul")

    -- Prepare viewport: isolate, maximize, set persp
    IsolateSelection.EnterIsolateSelectionMode()
    if viewport.numViews >= 2 then max tool maximize

    local savedViewportState = #(viewport.getType(), viewport.GetRenderLevel())
    max vpt persp user
    viewport.SetRenderLevel #smoothhighlights
    max zoomext sel
    max select none

    -- =============================================
    -- DIALOG
    -- =============================================

    local labelText = "Save as :   \\1_Archive\\" + (substituteString baseName ".max" "")

    try (destroyDialog ArchiveSaveAsSelection) catch()

    rollout ArchiveSaveAsSelection "Archive Selection" height:70 width:620 (
        edittext txtName labelText text:suggestedName
        button   btnOK "Save" height:22 width:120 align:#center offset:[0,8]

        fn restoreViewport = (
            max select all
            if viewport.numViews >= 2 then max tool maximize
            viewport.setType      savedViewportState[1]
            viewport.SetRenderLevel savedViewportState[2]
            IsolateSelection.ExitIsolateSelectionMode()
        )

        on btnOK pressed do (
            local safeName    = sanitizeFilename txtName.text
            local savePath    = archiveBasePath + safeName + ".max"
            local previewPath = archiveBasePath + safeName + ".jpg"

            -- Save nodes
            saveNodes selectedObjects savePath

            -- Save viewport preview
            local bmp = gw.getViewportDib()
            if bmp != undefined then (
                bmp.filename = previewPath
                save bmp
                close bmp
            ) else (
                format "Warning: viewport capture failed, no preview saved.\n"
            )

            destroyDialog ArchiveSaveAsSelection
            restoreViewport()
        )
    )

    CreateDialog ArchiveSaveAsSelection
)