macroScript Iconia_PasteAsset
category:"Iconia"
buttonText:"Paste Asset from Library"
tooltip:"Paste asset (Shift + Click for _proxy version)"
Icon:#("pasteasset",1)
(
    sourcePath = getclipboardText()
    
    -- Vérification si le presse-papier est vide
    if sourcePath == undefined or sourcePath == "" then
    (
        messageBox "Your clipboard is empty. Please copy a file path first."
        return false
    )

    -- Normalisation des slashes
    sanitizedPath = substituteString sourcePath "\\" "/"
    
    -- Variable finale qui contiendra le chemin à charger
    targetPath = sanitizedPath

    -- Si SHIFT est maintenu, on modifie le nom du fichier
    if keyboard.shiftPressed do
    (
        local dir = getFilenamePath sanitizedPath
        local filename = getFilenameFile sanitizedPath
        local ext = getFilenameType sanitizedPath
        
        -- Reconstruction du chemin avec _proxy
        targetPath = dir + filename + "_proxy" + ext
    )

    -- Vérification de l'existence du fichier (Original ou Proxy)
    if (doesFileExist targetPath) then
    (
        mergeMaxFile targetPath #select
        print ("Merged: " + targetPath) -- Affiche dans le listener ce qui a été merge
    )
    else
    (
        messageBox ("Error: The file could not be found:\n" + targetPath)
    )
)