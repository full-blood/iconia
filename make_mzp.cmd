@echo off
@REM ====================================================
@REM Final Iconia MZP Builder (Optimise, Corrige & Auto-Version)
@REM ====================================================
setlocal EnableDelayedExpansion

:: --- Config ---
set "repodir=%~dp0"
set "srcdir=%~dp0src"
set "outdir=%~dp0MAXScript_ZIP_Package"
set "lanDir=\\CgLibrary\CgLibrary\0-Documentation\3DS Max Configuration\3DS Max Plugins\Antoine\API\Iconia"
set "base=Iconia"
set count=1

:: --- Create output folder if needed ---
if not exist "%outdir%" mkdir "%outdir%"

:: --- Copie Iconia.mnx depuis 3ds Max vers src ---
set "mnxsrc=C:\Users\%USERNAME%\Autodesk\3ds Max 2026\User Settings\Iconia.mnx"
set "mnxdst=%srcdir%\Iconia.mnx"

if exist "%mnxsrc%" (
    copy /Y "%mnxsrc%" "%mnxdst%" >nul
    echo Iconia.mnx copie depuis 3ds Max vers src.
) else (
    echo AVERTISSEMENT : Iconia.mnx introuvable dans 3ds Max User Settings.
    echo Chemin verifie : %mnxsrc%
    echo Le build continue avec l'ancienne version si elle existe.
)
echo.

:: --- Lecture et Auto-Increment de la version ---
set "versionfile=%repodir%version.txt"
if not exist "%versionfile%" (
    > "%versionfile%" echo 1.0.0
    echo version.txt cree avec valeur 1.0.0
)
set /p currentver=<"%versionfile%"

:: Securite : retire les espaces invisibles potentiels
set "currentver=%currentver: =%"

:: Decoupage de la version (format attendu X.Y.Z)
for /f "tokens=1,2,3 delims=." %%a in ("%currentver%") do (
    set major=%%a
    set minor=%%b
    set patch=%%c
)
:: Calcul de la prochaine version
set /a nextpatch=patch + 1
set "nextver=%major%.%minor%.%nextpatch%"

echo.
echo ============================================
echo Version actuelle : %currentver%
echo ============================================
set /p dobump="Passer a la version %nextver% avant de builder ? (o/n) : "
if /I "%dobump%"=="o" (
    set "currentver=%nextver%"
    > "%versionfile%" echo !currentver!
    echo Version mise a jour : !currentver!
) else (
    echo On conserve la version : %currentver%
)
set "loaderid=Iconia_loader_%currentver:.=_%"
echo.

:: --- Copie version.txt vers outdir pour inclusion dans le MZP ---
copy /Y "%versionfile%" "%outdir%\version.txt" >nul

:: --- Generate mzp.run ---
set "runfile=%outdir%\mzp.run"

> "%runfile%" echo name "MZP Plugin"
>>"%runfile%" echo extract to $temp\Iconia_Setup
>>"%runfile%" echo run "$temp\Iconia_Setup\install_scripts.ms"
>>"%runfile%" echo drop "$temp\Iconia_Setup\install_scripts.ms"

echo mzp.run generated.

:: --- Generate install_scripts.ms dynamically ---
set "installfile=%outdir%\install_scripts.ms"

> "%installfile%" echo -- clearListener()
>>"%installfile%" echo print "install iconia menu..."
>>"%installfile%" echo.
>>"%installfile%" echo tempDir = getFilenamePath (getSourceFileName())
>>"%installfile%" echo userMacroDir = GetDir #userMacros
>>"%installfile%" echo startupDir = GetDir #userStartupScripts
>>"%installfile%" echo scriptsDir = GetDir #userScripts
>>"%installfile%" echo.
>>"%installfile%" echo -- Chemins cibles securises
>>"%installfile%" echo iconiaMNXPath     = "C:\\Users\\" + sysInfo.username + "\\Autodesk\\3ds Max 2026\\User Settings\\Iconia.mnx"
>>"%installfile%" echo iconiaLoaderPath  = startupDir + "\\%loaderid%.ms"
>>"%installfile%" echo iconiaVersionPath = scriptsDir + "\\Iconia\\version.txt"
>>"%installfile%" echo.
>>"%installfile%" echo fn safeCopy src dst = (
>>"%installfile%" echo     if doesFileExist src then (
>>"%installfile%" echo         local dstDir = getFilenamePath dst
>>"%installfile%" echo         if not doesFileExist dstDir then makeDir dstDir
>>"%installfile%" echo         if doesFileExist dst then deleteFile dst
>>"%installfile%" echo         (dotNetClass "System.IO.File").Copy src dst true
>>"%installfile%" echo         format "copied %% to %%\n" src dst
>>"%installfile%" echo     ) else (
>>"%installfile%" echo         format "WARNING: not found: %%\n" src
>>"%installfile%" echo     )
>>"%installfile%" echo )
>>"%installfile%" echo.
>>"%installfile%" echo safeCopy (tempDir + "Iconia.mnx")         iconiaMNXPath
>>"%installfile%" echo -- Les loaders en cours peuvent etre verrouilles : leur suppression ne doit jamais bloquer l'update.
>>"%installfile%" echo oldLoaders = getFiles (startupDir + "\\Iconia_loader*.ms")
>>"%installfile%" echo for f in oldLoaders where not ((toLower f) == (toLower iconiaLoaderPath)) do (
>>"%installfile%" echo     try (deleteFile f) catch (format "Loader conserve (verrouille) : %%\n" f)
>>"%installfile%" echo )
>>"%installfile%" echo -- Le nom versionne evite d'ecraser le loader actuellement execute.
>>"%installfile%" echo safeCopy (tempDir + "Iconia_loader.ms")   iconiaLoaderPath
>>"%installfile%" echo safeCopy (tempDir + "version.txt")        iconiaVersionPath
>>"%installfile%" echo.
>>"%installfile%" echo -- -----------------------------------------------
>>"%installfile%" echo -- Nettoyage des anciens fichiers "Iconia-" dans userMacros
>>"%installfile%" echo -- -----------------------------------------------
>>"%installfile%" echo oldFiles = getFiles (userMacroDir + "\\Iconia-*.mcr")
>>"%installfile%" echo join oldFiles (getFiles (userMacroDir + "\\Iconia_*.mcr"))
>>"%installfile%" echo for f in oldFiles do (
>>"%installfile%" echo     deleteFile f
>>"%installfile%" echo     format "Supprime : %%\n" f
>>"%installfile%" echo )
>>"%installfile%" echo.
>>"%installfile%" echo genericFiles = #(

set first=1
for %%F in ("%srcdir%\*") do (
    set "fname=%%~nxF"
    set "ext=%%~xF"
    if /I not "!fname!"=="install_scripts.ms" (
    if /I not "!fname!"=="mzp.run" (
    if /I not "!fname!"=="Iconia.mnx" (
    if /I not "!fname!"=="Iconia_loader.ms" (
    if /I not "!fname!"=="version.txt" (
    if /I not "!ext!"==".bak" (
    if /I not "!ext!"==".tmp" (
    if /I not "!fname!"=="Thumbs.db" (
        if !first!==1 (
            >>"%installfile%" echo     "!fname!"
            set first=0
        ) else (
            >>"%installfile%" echo     ,"!fname!"
        )
    ))))))))
)

>>"%installfile%" echo )
>>"%installfile%" echo.
>>"%installfile%" echo for fname in genericFiles do (
>>"%installfile%" echo     local dstPath = userMacroDir + "\\" + fname
>>"%installfile%" echo     safeCopy (tempDir + fname) dstPath
>>"%installfile%" echo.
>>"%installfile%" echo     -- On evalue (recharge) les scripts pour les activer sans redemarrer 3ds Max
>>"%installfile%" echo     local ext = toLower (getFilenameType fname)
>>"%installfile%" echo     if ext == ".mcr" or ext == ".ms" then (
>>"%installfile%" echo         try ( fileIn dstPath ) catch ( format "Erreur d'evaluation sur %%\n" fname )
>>"%installfile%" echo     )
>>"%installfile%" echo )
>>"%installfile%" echo.
>>"%installfile%" echo -- -----------------------------------------------
>>"%installfile%" echo -- Rechargement du Menu (3ds Max 2025+)
>>"%installfile%" echo -- -----------------------------------------------
>>"%installfile%" echo try (
>>"%installfile%" echo     -- On execute le loader qui vient d'etre installe pour inscrire la variable d'environnement
>>"%installfile%" echo     fileIn iconiaLoaderPath
>>"%installfile%" echo     print "Menu Iconia chargé avec succes !"
>>"%installfile%" echo ) catch (
>>"%installfile%" echo     format "Erreur lors du chargement du menu : %%\n" (getCurrentException())
>>"%installfile%" echo )
>>"%installfile%" echo.
>>"%installfile%" echo print "Installation termin?e."
>>"%installfile%" echo messageBox "Iconia v%currentver% installée avec succès !\n\nLe menu a été mis à jour."
>>"%installfile%" echo print "-- END --"

echo install_scripts.ms generated.

:: --- Determine next incremental MZP filename ---
:loop
set num=00%count%
set num=%num:~-3%
set "mzpfile=%outdir%\%base%_%num%.mzp"
if exist "%mzpfile%" (
    set /a count+=1
    goto loop
)

:: --- Build MZP ---
:: Etape 1 : fichiers src
pushd "%srcdir%"
"%ProgramFiles%\7-Zip\7z.exe" a -tzip "%mzpfile%" *
popd

:: Etape 2 : mzp.run + install_scripts.ms + version.txt depuis outdir
pushd "%outdir%"
"%ProgramFiles%\7-Zip\7z.exe" a -tzip "%mzpfile%" mzp.run install_scripts.ms version.txt
popd

:: --- Copie a la racine du repo ---
copy /Y "%mzpfile%" "%repodir%Iconia.mzp" >nul
echo Iconia.mzp copie a la racine.

:: --- Publication LAN ---
:: Le paquet est copie avant version.txt : les postes clients ne voient la nouvelle
:: version qu'une fois l'archive entierement disponible sur le partage.
if not exist "%lanDir%\" (
    echo ERREUR : partage LAN inaccessible : %lanDir%
    echo Le build local est conserve, mais aucune mise a jour LAN n'a ete publiee.
    goto afterLanPublish
)

echo Publication de Iconia v%currentver% sur le LAN...
copy /Y "%mzpfile%" "%lanDir%\Iconia.mzp" >nul
if errorlevel 1 (
    echo ERREUR : impossible de copier Iconia.mzp sur le partage LAN.
    goto afterLanPublish
)
copy /Y "%versionfile%" "%lanDir%\version.txt" >nul
if errorlevel 1 (
    echo ERREUR : Iconia.mzp est copie mais version.txt n'a pas pu etre publie.
    goto afterLanPublish
)
echo Publication LAN terminee : %lanDir%\

:afterLanPublish

echo.
echo ============================================
echo  Build termine : Iconia v%currentver%
echo  Archive : %mzpfile%
echo ============================================
echo.

:: --- Git push & GitHub Release ---
set /p dopublish="Publier aussi sur GitHub et creer la release ? (o/n) : "
if /I not "%dopublish%"=="o" goto done

pushd "%repodir%"
:: 1. On pousse le code sur le repo
echo.
echo Envoi du code sur GitHub...
git add .
git commit -m "release v%currentver%"
if errorlevel 1 (
    echo ERREUR : commit Git impossible. Release GitHub annulee.
    popd
    goto done
)
git push
if errorlevel 1 (
    echo ERREUR : push Git impossible. Release GitHub annulee.
    popd
    goto done
)

:: 2. On cree la release et on attache le .mzp
echo.
echo Creation de la Release GitHub v%currentver%...
gh release create "v%currentver%" "Iconia.mzp" --title "Mise a jour %currentver%" --generate-notes
if errorlevel 1 (
    echo ERREUR : creation de la release GitHub impossible.
    popd
    goto done
)

popd

echo.
echo ============================================
echo  Succes ! Release GitHub v%currentver% publiee.
echo  Verifie ici : https://github.com/full-blood/iconia/releases/latest
echo ============================================

:done
echo.
pause
