// Upload only an already inspected release. Does not change Storage rules.
const fs=require('node:fs');const path=require('node:path');const crypto=require('node:crypto');
async function main(){
 const file='build/public-beta-source/build/app/outputs/flutter-apk/app-release.apk';
 const bytes=fs.readFileSync(file);const sha=crypto.createHash('sha256').update(bytes).digest('hex');
 const approval=JSON.parse(fs.readFileSync('output/beta/apk-verification.json','utf8'));
 if(approval.sha256!==sha||!approval.passed) throw Error('APK verification does not match this artifact');
 const root=path.join(process.env.APPDATA,'npm/node_modules/firebase-tools/lib');
 const auth=require(path.join(root,'auth.js'));const scopes=require(path.join(root,'scopes.js'));
 const account=auth.getGlobalDefaultAccount();if(!account)throw Error('Firebase login required');
 const t=await auth.getAccessToken(account.tokens.refresh_token,[scopes.CLOUD_PLATFORM,scopes.FIREBASE_PLATFORM]);
 const headers={Authorization:`Bearer ${t.access_token}`};
 const bucket='hiker-circle.firebasestorage.app';const object=`releases/android/beta/hikercircle-1.1.0-beta.1-${sha.slice(0,12)}.apk`;
 const metadataUrl=`https://storage.googleapis.com/storage/v1/b/${bucket}/o/${encodeURIComponent(object)}`;
 let existing=await fetch(metadataUrl,{headers});let metadata;
 if(existing.status===404){
  const url=`https://storage.googleapis.com/upload/storage/v1/b/${bucket}/o?uploadType=media&ifGenerationMatch=0&name=${encodeURIComponent(object)}`;
  const response=await fetch(url,{method:'POST',headers:{...headers,'Content-Type':'application/vnd.android.package-archive'},body:bytes});
  if(!response.ok)throw Error('Upload HTTP '+response.status); metadata=await response.json();
 }else {if(!existing.ok)throw Error('Metadata HTTP '+existing.status);metadata=await existing.json();}
 if(Number(metadata.size)!==bytes.length)throw Error('Remote size mismatch');
 const downloadToken=metadata.metadata?.firebaseStorageDownloadTokens||crypto.randomUUID();
 const patched=await fetch(metadataUrl,{method:'PATCH',headers:{...headers,'Content-Type':'application/json'},body:JSON.stringify({contentType:'application/vnd.android.package-archive',contentDisposition:'attachment; filename="HikerCircle-1.1.0-beta.1.apk"',cacheControl:'public,max-age=86400,immutable',metadata:{...metadata.metadata,firebaseStorageDownloadTokens:downloadToken,sha256:sha,version:'1.1.0-beta.1',build:'3'}})});
 if(!patched.ok)throw Error('Metadata update HTTP '+patched.status);
 const url=`https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(object)}?alt=media&token=${downloadToken}`;
 const publicResponse=await fetch(url);if(!publicResponse.ok)throw Error('Public download HTTP '+publicResponse.status);
 const remoteSha=crypto.createHash('sha256');for await(const chunk of publicResponse.body)remoteSha.update(chunk);
 if(remoteSha.digest('hex')!==sha)throw Error('Public download checksum mismatch');
 const release={url,sha256:sha,sizeBytes:bytes.length,version:'1.1.0-beta.1',build:3,minAndroid:'7.0',published:'2026-09-09'};
 fs.writeFileSync('web/site/beta-release.json',JSON.stringify(release,null,2)+'\n');
 console.log(JSON.stringify(release));
}
main().catch(e=>{console.error(e.message);process.exitCode=1});
