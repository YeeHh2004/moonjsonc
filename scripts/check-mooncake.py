"""Audit the actual Mooncakes archive, without reading credentials or uploading."""
from pathlib import Path
import hashlib, json, re, subprocess, zipfile
root = Path(__file__).resolve().parent.parent
subprocess.run(['moon', 'package'], cwd=root, check=True)
version = re.search(r'^version\s*=\s*"([^"]+)"', (root/'moon.mod').read_text(), re.M)[1]
archive = root/f'_build/publish/YeeHh2004-moonjsonc-{version}.zip'
required = {'moon.mod','moon.pkg','pkg.generated.mbti','LICENSE','NOTICE.md','README.md',
            'scanner.mbt','parser.mbt','tree.mbt','location.mbt','visitor.mbt',
            'format.mbt','strip.mbt','edits.mbt','modify.mbt','transaction.mbt',
            'protocol/process.mbt','protocol/pkg.generated.mbti','docs/BEHAVIOR.md',
            'docs/COMPATIBILITY.md','docs/SELECTION.md','licenses/NOTICE',
            'licenses/MoonBit-core-LICENSE','examples/basic/main.mbt',
            'examples/editor/main.mbt','examples/transaction/main.mbt'}
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    names=set(z.namelist())
    assert required <= names, f'Missing files: {required-names}'
    for name in names:
        path=Path(name)
        assert not path.is_absolute() and '..' not in path.parts
        assert not any(part in {'.git','.moon','.mooncakes','node_modules','_build','dist'} for part in path.parts)
        assert path.name not in {'credentials.json','package-lock.json'}
        assert not name.startswith(('web/','scripts/','tests/','bridge/','cli/','examples/consumer/'))
    assert 'license = "MIT"' in z.read('moon.mod').decode()
print(json.dumps({'files':len(names),'bytes':archive.stat().st_size,
                  'sha256':hashlib.sha256(archive.read_bytes()).hexdigest()},indent=2))
