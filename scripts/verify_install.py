# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import os, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; BUILD=Path(os.environ.get('WTIVO_BUILD_DIR') or ROOT/'build').expanduser().resolve(); VCPKG_BIN=ROOT/'.deps'/'vcpkg'/'installed'/'x64-windows'/'bin'
_handles=[]
if os.name=='nt' and hasattr(os,'add_dll_directory'):
    candidates=[BUILD,VCPKG_BIN,Path(sys.executable).parent/'Lib'/'site-packages'/'torch'/'lib']
    for key in ('WTIVO_CUDA_HOME','CUDA_HOME','CUDA_PATH'):
        if os.environ.get(key): candidates.append(Path(os.environ[key])/'bin')
    for d in candidates:
        if d.exists():
            try: _handles.append(os.add_dll_directory(str(d)))
            except OSError: pass
            os.environ['PATH']=str(d)+os.pathsep+os.environ.get('PATH','')
sys.path.insert(0,str(BUILD))

import numpy as np
import torch
import wtivo_core, wtivo_gpupr, wtivo_vdb

print('WTiVo install verification')
print(' Python:',sys.version.split()[0]); print(' Torch :',torch.__version__); print(' CUDA  :',torch.version.cuda)
if not torch.cuda.is_available(): raise RuntimeError('PyTorch cannot see an NVIDIA CUDA GPU')
print(' GPU   :',torch.cuda.get_device_name(0)); print(' CC    :',torch.cuda.get_device_capability(0))

required={wtivo_core:('tetrahedralize_neighbors','largest_component','is_watertight'),wtivo_gpupr:('graph_cut_fast','surface_extraction_topology_cuda'),wtivo_vdb:('SparseUDF',)}
for mod,symbols in required.items():
    for name in symbols:
        if not hasattr(mod,name): raise RuntimeError(f'{mod.__name__} missing {name}')

# Tiny CGAL topology sanity test.
pts=np.array([[0,0,0],[1,0,0],[0,1,0],[0,0,1],[1,1,1]],dtype=np.float64)
verts,tets,nbrs=wtivo_core.tetrahedralize_neighbors(pts,2)
tets=np.asarray(tets); nbrs=np.asarray(nbrs)
if tets.ndim!=2 or tets.shape[1]!=4 or nbrs.shape!=tets.shape or len(tets)==0: raise RuntimeError('CGAL tetra sanity test failed')

# Tiny exact watertight test: a tetra shell has four faces, every edge degree 2.
faces=np.array([[0,2,1],[0,1,3],[0,3,2],[1,2,3]],dtype=np.int32)
wt,bad,*_=wtivo_core.is_watertight(faces,2)
if not wt or int(bad)!=0: raise RuntimeError('watertight checker sanity test failed')

# Tiny VDB construction + interface smoke. This does not assert a production-size contour.
tri_v=np.array([[.1,.1,.1],[.9,.1,.1],[.1,.9,.1],[.1,.1,.9]],dtype=np.float32)
tri_f=faces.copy()
field=wtivo_vdb.SparseUDF(tri_v,tri_f,1.0/64.0,3.0,2,False)
st=field.stats()
if int(st.get('active_voxels',0))<=0: raise RuntimeError('OpenVDB tiny field has no active voxels')

print('[PASS] wtivo_core CGAL/TBB')
print('[PASS] wtivo_core watertight audit')
print('[PASS] wtivo_vdb OpenVDB construction')
print('[PASS] wtivo_gpupr exports')
print('[PASS] NVIDIA CUDA visible')
if '--e2e' in sys.argv:
    # End-to-end smoke of the .npy bridge used by the ComfyUI node (needs the GPU).
    import subprocess, tempfile
    with tempfile.TemporaryDirectory(prefix='wtivo_verify_') as td:
        td=Path(td)
        # icosphere-ish closed mesh via a UV sphere
        nu,nv=48,96
        th=np.linspace(0,np.pi,nu); ph=np.linspace(0,2*np.pi,nv,endpoint=False)
        V=[[0,0,1]]+[[np.sin(t)*np.cos(p),np.sin(t)*np.sin(p),np.cos(t)] for t in th[1:-1] for p in ph]+[[0,0,-1]]
        F=[]
        for j in range(nv): F.append([0,1+j,1+(j+1)%nv])
        for i in range(nu-3):
            for j in range(nv):
                a=1+i*nv+j; b=1+i*nv+(j+1)%nv; c=a+nv; d=b+nv; F+= [[a,c,b],[b,c,d]]
        last=len(V)-1
        for j in range(nv): F.append([last,last-nv+(j+1)%nv,last-nv+j])
        np.save(td/'vi.npy',np.asarray(V,dtype=np.float64)); np.save(td/'fi.npy',np.asarray(F,dtype=np.int32))
        cmd=[sys.executable,str(ROOT/'wtivo.py'),'--input-vertices-npy',str(td/'vi.npy'),'--input-faces-npy',str(td/'fi.npy'),
             '--output-vertices-npy',str(td/'vo.npy'),'--output-faces-npy',str(td/'fo.npy'),
             '--input-res','128','--final-res','128','--proxy_points','200000','--threads','4']
        r=subprocess.run(cmd,capture_output=True,text=True)
        print(r.stdout[-1500:]); print(r.stderr[-1500:])
        if r.returncode!=0 or not (td/'vo.npy').exists(): raise RuntimeError('npy bridge end-to-end run failed')
        vo=np.load(td/'vo.npy'); fo=np.load(td/'fo.npy')
        if vo.ndim!=2 or vo.shape[1]!=3 or fo.shape[1]!=3 or len(fo)==0: raise RuntimeError('npy bridge output malformed')
        if 'watertight=True' not in r.stdout: raise RuntimeError('npy bridge output not watertight')
        print(f'[PASS] npy bridge end-to-end ({len(vo):,} v / {len(fo):,} f)')
print('WTiVo is ready.')
