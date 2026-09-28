from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
p=root/'index.html';s=p.read_text()
for tag,id,file in [('style','roster081Style','src/roster.css'),('script','roster082Script','src/roster.js'),('script','eligibility083Script','src/eligibility.js'),('script','attendance084Script','src/attendance.js'),('script','eventEdit080Script','src/event-edit.js'),('script','schedule085Script','src/schedule-tools.js'),('style','offlineWorkspace088Style','src/offline-workspace.css'),('script','offlineStore088Script','src/offline-store.js'),('script','offlineWorkspace088Script','src/offline-workspace.js'),('script','chatDrafts090Script','src/chat-drafts.js'),('style','chatDrafts090Style','src/chat-drafts.css')]:
 s,n=re.subn(rf'(<{tag} id="{id}">).*?(</{tag}>)',lambda m:m[1]+'\n'+(root/file).read_text()+'\n'+m[2],s,flags=re.S)
 assert n==1,(id,n)
p.write_text(s)
