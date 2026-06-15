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

    fn stripDatePrefix fname = (
        local c2 = substring fname 1 2
        local c4 = substring fname 1 4
        local validYY  = #("22","23","24","25","26")
        local validYYYY = #("2022","2023","2024","2025","2026")

        if (findItem validYYYY c4 > 0) and (substring fname 9 1 == "_") then
            return (substring fname 9 fname.count)

        if (findItem validYY c2 > 0) and (substring fname 7 1 == "_") then
            return (substring fname 7 fname.count)

        return fname
    )

    fn getTimestamp = (
        local d = getLocalTime()
        local yyyy = d[1] as string
        local mm   = if d[2] < 10 then ("0" + d[2] as string) else (d[2] as string)
        local dd   = if d[4] < 10 then ("0" + d[4] as string) else (d[4] as string)
        local hh   = if d[5] < 10 then ("0" + d[5] as string) else (d[5] as string)
        local mn   = if d[6] < 10 then ("0" + d[6] as string) else (d[6] as string)
        return (yyyy + mm + dd + hh + mn)
    )

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

    local originalSelection = selection as array
    local archiveDir      = maxFilePath + "1_Archive\\"
    local cleanName       = stripDatePrefix maxFileName
    local timestamp       = getTimestamp()
    local baseName        = substituteString (timestamp + cleanName) ".max" "_"
    local archiveBasePath = archiveDir + baseName

    local suggestedName = try (
        originalSelection[1].layer.name + "_" + originalSelection[1].name
    ) catch (
        originalSelection[1].name
    )

    HiddenDosCommand ("mkdir \"" + archiveDir + "\" 2>nul")

    -- =============================================
    -- DISPLAY STATE & ISOLATION LOGIC
    -- =============================================
    
    -- 1. Inverser la sélection
    max select invert
    local invertedSelection = selection as array
    
    local tempSetName = "_TempArchiveHidden_"
    local needsRestore = false

    -- 2. Créer le set temporaire uniquement s'il y a des objets à masquer 
    -- (gère le cas où la sélection d'origine est déjà isolée ou seule)
    if invertedSelection.count > 0 then (
        selectionSets[tempSetName] = invertedSelection
        hide selectionSets[tempSetName]
        needsRestore = true
    )

    -- 3. Réinverser (récupérer la sélection de base)
    select originalSelection
    
    -- Préparation du Viewport
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
            -- Restaurer le format du viewport
            if viewport.numViews >= 2 then max tool maximize
            viewport.setType      savedViewportState[1]
            viewport.SetRenderLevel savedViewportState[2]
            
            -- Restaurer l'affichage via le set temporaire
            if needsRestore then (
                try (
                    unhide selectionSets[tempSetName]
                    deleteItem selectionSets tempSetName
                ) catch()
            )
            
            -- Restaurer la sélection initiale
            select originalSelection
        )

        on btnOK pressed do (
            local safeName    = sanitizeFilename txtName.text
            local savePath    = archiveBasePath + safeName + ".max"
            local previewPath = archiveBasePath + safeName + ".jpg"

            -- Sauvegarde (utilise originalSelection pour garantir qu'on exporte les bons objets)
            saveNodes originalSelection savePath

            -- Capture d'écran
            local bmp = gw.getViewportDib()
            if bmp != undefined then (
                bmp.filename = previewPath
                save bmp
                close bmp
            ) else (
                format "Warning: viewport capture failed, no preview saved.\n"
            )

            destroyDialog ArchiveSaveAsSelection
        )
        
        on ArchiveSaveAsSelection close do (
            restoreViewport()
        )
    )

    CreateDialog ArchiveSaveAsSelection
)