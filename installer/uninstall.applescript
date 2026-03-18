--
-- DarwinFUSE Uninstaller (multilingual)
--
-- AppleScript app that removes all DarwinFUSE files.
-- Compiled into an .app bundle via osacompile during pkg build.
--

-- Detect system language (first two characters)
set lang to do shell script "defaults read -g AppleLocale | cut -c1-2"

-- Localized strings
if lang is "de" then
	set confirmTitle to "DarwinFUSE deinstallieren"
	set confirmMsg to "DarwinFUSE wird von Ihrem System entfernt." & return & return & "FUSE-Programme (sshfs, encfs, ntfs-3g, ...) funktionieren danach nicht mehr, bis Sie DarwinFUSE oder macFUSE erneut installieren."
	set btnCancel to "Abbrechen"
	set btnUninstall to "Deinstallieren"
	set successMsg to "DarwinFUSE wurde erfolgreich entfernt."
	set failMsg to "Deinstallation fehlgeschlagen:"
else if lang is "fr" then
	set confirmTitle to "Désinstaller DarwinFUSE"
	set confirmMsg to "DarwinFUSE sera supprimé de votre système." & return & return & "Les programmes FUSE (sshfs, encfs, ntfs-3g, ...) ne fonctionneront plus jusqu'à la réinstallation de DarwinFUSE ou macFUSE."
	set btnCancel to "Annuler"
	set btnUninstall to "Désinstaller"
	set successMsg to "DarwinFUSE a été supprimé avec succès."
	set failMsg to "La désinstallation a échoué :"
else if lang is "es" then
	set confirmTitle to "Desinstalar DarwinFUSE"
	set confirmMsg to "DarwinFUSE se eliminará de su sistema." & return & return & "Los programas FUSE (sshfs, encfs, ntfs-3g, ...) dejarán de funcionar hasta que reinstale DarwinFUSE o macFUSE."
	set btnCancel to "Cancelar"
	set btnUninstall to "Desinstalar"
	set successMsg to "DarwinFUSE se ha eliminado correctamente."
	set failMsg to "La desinstalación ha fallado:"
else if lang is "ja" then
	set confirmTitle to "DarwinFUSEをアンインストール"
	set confirmMsg to "DarwinFUSEをシステムから削除します。" & return & return & "FUSEプログラム（sshfs、encfs、ntfs-3gなど）はDarwinFUSEまたはmacFUSEを再インストールするまで動作しなくなります。"
	set btnCancel to "キャンセル"
	set btnUninstall to "アンインストール"
	set successMsg to "DarwinFUSEが正常に削除されました。"
	set failMsg to "アンインストールに失敗しました："
else if lang is "zh" then
	set confirmTitle to "卸载DarwinFUSE"
	set confirmMsg to "将从系统中移除DarwinFUSE。" & return & return & "FUSE程序（sshfs、encfs、ntfs-3g等）将无法使用，直到您重新安装DarwinFUSE或macFUSE。"
	set btnCancel to "取消"
	set btnUninstall to "卸载"
	set successMsg to "DarwinFUSE已成功移除。"
	set failMsg to "卸载失败："
else
	-- English (default)
	set confirmTitle to "Uninstall DarwinFUSE"
	set confirmMsg to "This will remove DarwinFUSE from your system." & return & return & "FUSE-based programs (sshfs, encfs, ntfs-3g, ...) will stop working until you reinstall DarwinFUSE or macFUSE."
	set btnCancel to "Cancel"
	set btnUninstall to "Uninstall"
	set successMsg to "DarwinFUSE has been removed successfully."
	set failMsg to "Uninstall failed:"
end if

set dialogResult to display dialog confirmMsg buttons {btnCancel, btnUninstall} default button btnCancel with icon caution with title confirmTitle

if button returned of dialogResult is btnUninstall then

	set uninstallScript to "
rm -f  /usr/local/lib/libdarwinfuse.a
rm -f  /usr/local/lib/libfuse.2.dylib
rm -f  /usr/local/lib/libfuse.dylib
rm -f  /usr/local/lib/libfuse.la
rm -f  /usr/local/lib/libdarwinfuse.2.dylib
rm -f  /usr/local/lib/libdarwinfuse.dylib
rm -rf /usr/local/include/darwinfuse
rm -rf /usr/local/include/fuse
rm -f  /usr/local/include/fuse.h
rm -f  /usr/local/lib/pkgconfig/darwinfuse.pc
rm -f  /usr/local/lib/pkgconfig/fuse.pc
rm -rf /usr/local/share/darwinfuse
pkgutil --forget io.darwinfuse.pkg.core 2>/dev/null
rm -rf '/Applications/DarwinFUSE'
"

	try
		do shell script uninstallScript with administrator privileges
		display dialog successMsg buttons {"OK"} default button "OK" with title confirmTitle
	on error errMsg
		display dialog failMsg & return & return & errMsg buttons {"OK"} default button "OK" with icon stop with title confirmTitle
	end try

end if
