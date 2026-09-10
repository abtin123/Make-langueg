import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location('complete_languages', Path('tool/l10n/complete_languages.py'))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

seen=[]
def fake_batch(texts, target):
    seen.extend(texts)
    return [f'TR({x})' for x in texts]

mod.google_batch = fake_batch
value, parts = mod.protect('متن فارسی {name}')
out = mod.restore(fake_batch([value], 'de')[0], parts)
assert seen == ['متن فارسی \ue0000\ue001']
assert out == 'TR(متن فارسی {name})'
print('translation-value test: OK')
