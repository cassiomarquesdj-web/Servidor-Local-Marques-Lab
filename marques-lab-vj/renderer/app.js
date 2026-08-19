const state={bpm:128,col:2,layer:'LOGO',playing:false,rec:false,auto:true,sync:false,opacity:100,volume:80};
const layers=[
{name:'LOGO',color:'#9a52ff',cells:['TBT','TBT','TBT','TBT','TBT','TBT','TBT','TBT','TBT','TBT'],type:'text'},
{name:'TEXTO',color:'#ff8d30',cells:['AO VIVO','DJ CÁSSIO','TBT','É DIFERENTE','A FESTA','CONTINUA','SENTE','O GRAVE','NO PEITO','TBT DOS<br>MANINHOS'],type:'text'},
{name:'CAMERA',color:'#32a7ff',cells:['CAM 01','CAM 02','CAM 03','CAM 04','CAM 05','CAM 06','CAM 07','CAM 08','CAM 09','CAM 10'],type:'image'},
{name:'MOTION',color:'#43d742',cells:['GRID','HEX','LINES','WAVE','SPIRAL','EDGE','TUNNEL','GLOW','SCAN','FLOW'],type:'motion'},
{name:'FX',color:'#ff4157',cells:['RINGS','GLITCH','RGB','GRAIN','BLOOM','DISTORT','STROBE','CHROMA','SHAKE','PARTICLES'],type:'fx'},
{name:'BACKGROUND',color:'#e1b33e',cells:['BLACK','SMOKE','PURPLE','BLUE','RED','CYAN','DARK','LIGHTS','VOID','TEXTURE'],type:'image'}
];
const effects=[['Remove Background (IA)',true],['Outline',true],['Glow',true],['RGB Split',true],['Pulse (Audio)',true]];
function renderMeter(){const e=document.querySelector('#meter');e.innerHTML='';for(let i=0;i<34;i++){const s=document.createElement('span');s.style.height=`${8+Math.random()*22}px`;e.appendChild(s)}}
function renderSpectrum(){const e=document.querySelector('#spectrum');e.innerHTML='';for(let i=0;i<30;i++){const s=document.createElement('span');s.style.height=`${12+Math.random()*55}px`;e.appendChild(s)}}
function renderMetrics(){const e=document.querySelector('#audioMetrics');const v=[64,81,55,73,88,70];e.innerHTML=['KICK','BASS','MID','TREBLE','VOLUME','ENERGY'].map((n,i)=>`<div class="metric"><span>${n}</span><div class="metric-bar"><div class="metric-fill" style="width:${v[i]}%"></div></div><strong>${v[i]}%</strong></div>`).join('')}
function renderLayers(){const g=document.querySelector('#layersGrid');g.innerHTML='<div></div>';for(let c=1;c<=10;c++)g.insertAdjacentHTML('beforeend',`<div class="col-head ${c===state.col?'active':''}">${String(c).padStart(2,'0')}</div>`);layers.forEach(layer=>{g.insertAdjacentHTML('beforeend',`<div class="grid-label"><span class="layer-color" style="background:${layer.color}"></span>${layer.name}</div>`);layer.cells.forEach((cell,i)=>{const active=i+1===state.col&&layer.name===state.layer?'active':'';g.insertAdjacentHTML('beforeend',`<button class="cell ${layer.type} ${active}" data-layer="${layer.name}" data-col="${i+1}"><span>${cell}</span></button>`)});});g.querySelectorAll('.cell').forEach(b=>b.addEventListener('click',()=>{state.layer=b.dataset.layer;state.col=Number(b.dataset.col);renderLayers();triggerCell()}));g.querySelectorAll('.col-head').forEach((el,i)=>{if(!i) return;el.addEventListener('click',()=>{state.col=i;renderLayers()})})}
function triggerCell(){document.querySelector('.preview-kicker').textContent=`${state.layer} • COLUNA ${String(state.col).padStart(2,'0')}`;document.querySelector('#previewSource').textContent=state.layer==='CAMERA'?'CAMERA • iPhone de Cassio':`LAYER • ${state.layer}`}
function renderEffects(){document.querySelector('#effectsCount').textContent=`(${effects.length})`;const e=document.querySelector('#effectsList');e.innerHTML=effects.map((x,i)=>`<div class="effect ${x[1]?'':'disabled'}"><button class="toggle" data-i="${i}">${x[1]?'◉':'○'}</button><span>${x[0]}</span><button class="gear">⚙</button><button class="gear">⌄</button></div>`).join('');e.querySelectorAll('.toggle').forEach(b=>b.addEventListener('click',()=>{const i=Number(b.dataset.i);effects[i][1]=!effects[i][1];renderEffects()}))}
function updateBpm(){const v=state.bpm.toFixed(1);document.querySelector('#bpmReadout').textContent=v;document.querySelector('#audioBpm').textContent=v}
function setMode(studio){document.querySelector('#studioMode').classList.toggle('active',studio);document.querySelector('#performanceMode').classList.toggle('active',!studio)}
function showHelp(){document.querySelector('#helpPanel').classList.remove('hidden')}
async function importMedia(){const files=await window.marquesLabVJ.pickMedia();if(!files.length)return;const f=files[0];const v=document.querySelector('#mediaPreview');v.src='file://'+f.replaceAll('\\','/');v.style.display='block';v.play().catch(()=>{});document.querySelector('#previewMode').textContent='INPUT • '+f.split('/').pop()}
function bind(){
 document.querySelectorAll('.lib-item').forEach(b=>b.addEventListener('click',()=>{document.querySelectorAll('.lib-item').forEach(x=>x.classList.remove('active'));b.classList.add('active')}));
 document.querySelector('#tapBtn').addEventListener('click',()=>{state.bpm=124+Math.random()*10;updateBpm()});
 document.querySelector('#playBtn').addEventListener('click',()=>{state.playing=!state.playing;document.querySelector('#playBtn').textContent=state.playing?'❚❚':'▶'});
 document.querySelector('#recBtn').addEventListener('click',()=>{state.rec=!state.rec;document.querySelector('#recBtn').classList.toggle('active',state.rec)});
 document.querySelector('#syncBtn').addEventListener('click',()=>{state.sync=!state.sync;document.querySelector('#syncBtn').classList.toggle('accent',state.sync)});
 document.querySelector('#studioMode').addEventListener('click',()=>setMode(true));document.querySelector('#performanceMode').addEventListener('click',()=>setMode(false));
 document.querySelector('#opacitySlider').addEventListener('input',e=>{state.opacity=Number(e.target.value);document.querySelector('#opacityReadout').textContent=state.opacity+'%'});
 document.querySelector('#volumeSlider').addEventListener('input',e=>state.volume=Number(e.target.value));
 document.querySelector('#addEffect').addEventListener('click',()=>{effects.push(['Pulse (Beat)',true]);renderEffects()});
 document.querySelector('#settingsBtn').addEventListener('click',showHelp);document.querySelector('#closeHelp').addEventListener('click',()=>document.querySelector('#helpPanel').classList.add('hidden'));
 document.querySelector('#importBtn').addEventListener('click',importMedia);
 document.querySelector('#newCollection').addEventListener('click',()=>alert('Coleções personalizadas entram na próxima camada do projeto.'));
 document.querySelectorAll('.tab').forEach(t=>t.addEventListener('click',()=>{document.querySelectorAll('.tab').forEach(x=>x.classList.remove('active'));t.classList.add('active')}));
 document.querySelectorAll('[data-action]').forEach(b=>b.addEventListener('click',()=>document.querySelector('.preview-canvas').animate([{filter:'brightness(1)'},{filter:'brightness(1.65)'},{filter:'brightness(1)'}],{duration:240})));
 window.addEventListener('keydown',e=>{if(e.code==='Space'){e.preventDefault();document.querySelector('#playBtn').click()}if(e.key.toLowerCase()==='r')document.querySelector('#recBtn').click();if((e.metaKey||e.ctrlKey)&&e.key.toLowerCase()==='o'){e.preventDefault();importMedia()}});
}
window.marquesLabVJ?.on('open-import',importMedia);window.marquesLabVJ?.on('show-shortcuts',showHelp);
renderMeter();renderSpectrum();renderMetrics();renderLayers();renderEffects();bind();setInterval(()=>{renderMeter();renderSpectrum();document.querySelector('#confidence').textContent=(96+Math.round(Math.random()*3))+'%'},240);