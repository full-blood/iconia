/*
    Iconia_FileChecker_ProxyProof.ms
    PREUVE ISOLÉE — conversion d'un asset ouvert en Corona Proxies.
    Le .max source est sauvegardé avant toute conversion ; la scène proxy est
    ensuite enregistrée dans <nom>_proxy.max, dans le même dossier.
*/

try(destroyDialog IconiaCoronaProxyProof)catch()

    fn icpSanitizeFilename value = (
        local clean = value as string
        for illegal in #("\\", "/", ":", "*", "?", "\"", "<", ">", "|") do clean = substituteString clean illegal "_"
        clean
    )

    fn icpGetProxyCandidates = (
        local result = #()
        for node in objects where isValidNode node do (
            -- Chaque géométrie est exportée séparément. Les helpers, caméras,
            -- lumières et proxies existants restent intacts.
            if (superClassOf node == GeometryClass) and not (isKindOf node CProxy) do append result node
        )
        result
    )

    fn icpBuildReport sourcePath proxyPath converted skipped = (
        local reportPath = getFilenamePath proxyPath + getFilenameFile proxyPath + "_report.txt"
        local report = createFile reportPath
        format "Corona Proxy conversion proof\n" to:report
        format ("Source saved first: " + sourcePath + "\n") to:report
        format ("Proxy scene: " + proxyPath + "\n") to:report
        format ("Converted nodes: " + (converted.count as string) + "\n") to:report
        for pair in converted do format ("  OK: " + pair[1] + " -> " + pair[2] + "\n") to:report
        format ("Skipped nodes: " + (skipped.count as string) + "\n") to:report
        for item in skipped do format ("  SKIP: " + item + "\n") to:report
        close report
        reportPath
    )

global icpConvertSceneToProxy
fn icpConvertSceneToProxy silent:false = (
        if maxFileName == "" or maxFilePath == "" then (
            messageBox "Enregistrez d'abord le .max source avant la conversion." title:"CONVERT TO PROXY"
            return false
        )

        local sourcePath = maxFilePath + maxFileName
        local sourceStem = getFilenameFile maxFileName
        if matchPattern sourceStem pattern:"*_proxy" ignoreCase:true then (
            messageBox "Ce fichier semble déjà être une scène proxy. Ouvrez le .max source sans proxy." title:"CONVERT TO PROXY"
            return false
        )

        local candidates = icpGetProxyCandidates()
        if candidates.count == 0 then (
            messageBox "Aucune géométrie source éligible à convertir." title:"CONVERT TO PROXY"
            return false
        )

        local proxyScenePath = maxFilePath + sourceStem + "_proxy.max"
        local cgeoPaths = #()
        for node in candidates do append cgeoPaths (maxFilePath + "crp_" + icpSanitizeFilename node.name + ".cgeo")

        local existingOutputs = #()
        for path in cgeoPaths where doesFileExist path do append existingOutputs path
        if doesFileExist proxyScenePath do append existingOutputs proxyScenePath

        if existingOutputs.count > 0 then (
            local warning = "Les fichiers suivants existent déjà et seront écrasés :\n\n"
            for path in existingOutputs do warning += path + "\n"
            warning += "\nContinuer ?"
            if not (queryBox warning title:"CONVERT TO PROXY — fichiers existants" beep:true) do return false
        )

        -- ÉTAPE IMPÉRATIVE : garantit le .max original, sans aucun proxy.
        if not saveMaxFile sourcePath quiet:true then (
            messageBox ("Impossible de sauvegarder le .max source :\n" + sourcePath) title:"CONVERT TO PROXY"
            return false
        )

        -- CProxy.fromScene est exécuté à la première frame : le .cgeo reste statique,
        -- sans cache d'animation. Ne modifie pas la timeline de la scène.

        local converted = #()
        local skipped = #()
        local deletedSources = #()
        local proxyPropertiesReported = false

        undo "Convert Scene To Corona Proxies" on (
            for index = 1 to candidates.count do (
                local sourceNode = candidates[index]
                local cgeoPath = cgeoPaths[index]
                if not isValidNode sourceNode then (
                    append skipped ("Node invalide : " + (index as string))
                ) else (
                    local originalName = sourceNode.name
                    local originalTransform = sourceNode.transform
                    local originalParent = sourceNode.parent
                    local originalLayer = sourceNode.layer
                    local originalWireColor = sourceNode.wireColor
                    local originalVisibility = sourceNode.visibility
                    local originalHidden = sourceNode.isHidden
                    local newProxy = undefined

                    try(
                        -- Écrasement seulement après consentement explicite ci-dessus.
                        if doesFileExist cgeoPath do deleteFile cgeoPath
                        -- Corona 10 fromScene retourne 0, pas le node. On récupère donc
                        -- le CProxy créé via son chemin .cgeo exact.
                        at time animationRange.start CProxy.ProxyFp.fromScene (CProxy()) sourceNode cgeoPath
                        for candidateProxy in objects do (
                            if (try(candidateProxy.filename == cgeoPath)catch(false)) do newProxy = candidateProxy
                        )
                    )catch(
                        newProxy = undefined
                        append skipped (originalName + " : " + (getCurrentException() as string))
                    )

                    if newProxy != undefined and isValidNode newProxy and doesFileExist cgeoPath then (
                        -- Remplacement de la source, conservation de l'organisation scène.
                        newProxy.name = "crp_" + originalName
                        if originalParent != undefined and isValidNode originalParent do newProxy.parent = originalParent
                        newProxy.transform = originalTransform
                        if originalLayer != undefined do originalLayer.addNode newProxy
                        newProxy.wireColor = originalWireColor
                        newProxy.visibility = originalVisibility
                        newProxy.isHidden = originalHidden

                        -- Corona / 3ds Max 2026 : previzType 2 = Point Cloud.
                        try(newProxy.previzType = 2)catch(append skipped (originalName + " : Point Cloud non configuré"))

                        -- Ne jamais exporter d'animation : fromScene produit un .cgeo statique
                        -- à animationRange.start. Les propriétés Corona disponibles sont listées
                        -- une seule fois dans le Listener pour confirmer la version installée.
                        if not proxyPropertiesReported then (
                            format "Corona Proxy properties for verification:\n"
                            showProperties newProxy
                            proxyPropertiesReported = true
                        )

                        delete sourceNode
                        append deletedSources sourceNode
                        append converted #("crp_" + originalName, cgeoPath)
                    ) else (
                        append skipped (originalName + " : export .cgeo échoué")
                        if doesFileExist cgeoPath do deleteFile cgeoPath
                    )
                )
            )
        )

        if converted.count == 0 then (
            messageBox "Aucun proxy n'a été créé. Le .max source reste sauvegardé, sans proxy." title:"CONVERT TO PROXY"
            return false
        )

        if not saveMaxFile proxyScenePath quiet:true then (
            messageBox ("Les .cgeo sont créés, mais la sauvegarde proxy a échoué :\n" + proxyScenePath + "\n\nLe .max source sans proxy reste protégé :\n" + sourcePath) title:"CONVERT TO PROXY"
            return false
        )

        local reportPath = icpBuildReport sourcePath proxyScenePath converted skipped
        if not silent do (
            messageBox (
                "Conversion terminée.\n\n" +
            "Source sans proxy sauvegardée :\n" + sourcePath + "\n\n" +
            "Scène proxy créée :\n" + proxyScenePath + "\n\n" +
            "Proxies créés : " + (converted.count as string) + "\n" +
            "Ignorés / avertissements : " + (skipped.count as string) + "\n\n" +
            "Rapport :\n" + reportPath
            ) title:"CONVERT TO PROXY"
        )
        true
    )

    rollout IconiaCoronaProxyProof "Iconia — Corona Proxy Proof" width:520 height:218 (
        label info "Test isolé avant intégration dans FileChecker" pos:[20,18] width:480 height:18 align:#center
        label details "• Sauvegarde d'abord le .max source sans proxy\n• Exporte chaque node Geometry séparément dans le même dossier\n• Remplace chaque source par crp_<nom>, preview Point Cloud\n• Sauvegarde ensuite <nom>_proxy.max\n• Avertit avant tout écrasement .cgeo ou _proxy.max" pos:[24,48] width:472 height:84
        button btn_convert "CONVERT TO PROXY" pos:[125,154] width:270 height:38
        on btn_convert pressed do icpConvertSceneToProxy()
    )
    if (try(IconiaProxyProofRunNow == true)catch(false)) then (
        icpConvertSceneToProxy silent:true
    ) else (
        createDialog IconiaCoronaProxyProof
    )
