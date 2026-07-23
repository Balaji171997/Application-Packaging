# Knowledge Base Summary  (894 packages)

- Template split: v3 = 782, v4 = 112
- Installer types: EXE=535, MSI=351, Unknown=8
- EXE engines: unknown-args=143, NSIS=94, InnoSetup=79, vendor-custom=73, Burn/WiX/other=60
- Auto-update recipes seen: scheduled-task=36, update-policy/config=28, vendor-updater-service/task=13, stop-update-service=10, disable-update-service=3

## Top vendors (by package count)
- **Microsoft** (40) - types: EXE/MSI/Unknown; install args e.g. `/quiet /norestart /log "$configToolKitLogDir\$setuplogfolder\$setuplogName"`; auto-update: scheduled-task
- **Vector** (35) - types: EXE/MSI; install args e.g. `/s /u all keyman`; auto-update: scheduled-task
- **Autodesk** (30) - types: MSI/EXE; install args e.g. `--silent`; auto-update: update-policy/config
- **DassaultSystems** (22) - types: EXE/MSI; install args e.g. `/exenoupdates /exelog "$configToolKitLogDir\$setuplogName" /exenoui /quiet`; auto-update: update-policy/config
- **Adobe** (21) - types: MSI/EXE; install args e.g. `--silent`; auto-update: vendor-updater-service/task,scheduled-task
- **Citrix** (17) - types: EXE/MSI/Unknown; install args e.g. `/logpath "$configToolKitLogDir\$setuplogfolderpr" /removeall /noreboot /quiet`; auto-update: scheduled-task
- **Siemens** (15) - types: EXE/MSI/Unknown; install args e.g. `/s /v"/qn /l*v "$($configToolkitLogDir)\$($VWG_appFullName)_Setup_Install.log" ADDLOCAL="FlomasterApplication,Compilers" SALTLICENSE=1717@mbddlcwppa09493 /norestart"`; auto-update: 
- **CarlZeiss** (15) - types: EXE/MSI; install args e.g. `/S`; auto-update: stop-update-service,update-policy/config,disable-update-service
- **Altair** (15) - types: EXE; install args e.g. `-i silent -f "$dirSupportFiles\installvariables.properties" -DACCEPT_EULA=YES`; auto-update: 
- **MathWorks** (14) - types: EXE; install args e.g. `/S`; auto-update: 
- **SAP** (14) - types: EXE/Unknown; install args e.g. `/Silent`; auto-update: scheduled-task
- **Oracle** (13) - types: MSI/EXE; install args e.g. ``; auto-update: 
- **dSPACE** (10) - types: EXE; install args e.g. `--install --load "$dirFiles\dSPACE.ini" --ignorependingreboot --noreboot --nogui --logfolder "$configToolKitLogDir\$setuplogfolder"`; auto-update: 
- **Ansys** (9) - types: EXE/MSI; install args e.g. `-Silent -Discovery -SpaceClaim`; auto-update: 
- **VW** (8) - types: EXE/MSI; install args e.g. `/partner=$InstallForVendor`; auto-update: 
- **Brother** (7) - types: MSI/EXE; install args e.g. `-s -f1"$dirFiles\Install.iss" /f2"$($configToolkitLogDir)\$($VWG_appFullName)_Setup_$($deploymentType+'.log')"`; auto-update: 
- **MAN** (7) - types: EXE/MSI/Unknown; install args e.g. `lan export profile folder="$backupConf"`; auto-update: 
- **WibuSystems** (7) - types: MSI/EXE; install args e.g. `/RS:{00060000-0000-1004-8002-0000C06B5161}`; auto-update: 
- **PaloAltoNetworks** (6) - types: MSI; install args e.g. ``; auto-update: 
- **GammaTechnologies** (6) - types: EXE; install args e.g. `--mode unattended --enable-components gtsuite,examples,tutorials,gtsimerics,gtconverge,gttecplot,gttaitherm --disable-components flexlm,client_only --installdir "$envProgramFilesx86\GTI" --tempdir "$envProgramdata\GT-SUITE_working_data\gtidata\dbdir" --licensing network --flexlm_license 0 --host1 port@host --client_gtihome "$envProgramFilesx86\GTI" --force_shutdown_silent 0 --create_desktop_shortcuts_silent 0`; auto-update: 
- **PTC** (6) - types: MSI/EXE; install args e.g. ` -f "$dirFiles\mksclient.properties"`; auto-update: 
- **LexCom** (6) - types: EXE; install args e.g. `/S`; auto-update: scheduled-task,stop-update-service
- **ATS** (5) - types: MSI; install args e.g. `IACCEPTMSODBCSQLLICENSETERMS=YES`; auto-update: 
- **JetBrains** (5) - types: EXE; install args e.g. `/S /CONFIG="$dirFiles\silent.config" /LOG="$configToolKitLogDir\$setuplogName" /D=$InstallDir`; auto-update: 
- **Woelfel** (5) - types: EXE/MSI; install args e.g. `/S`; auto-update: 
