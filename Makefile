export PYTHONPATH := $(CURDIR)/lib/:$(CURDIR)/tests/
PYTHON := python
KODI_PYTHON_ABIS := 3.0.0 2.25.0

name = $(shell xmllint --xpath 'string(/addon/@id)' addon.xml)
version = $(shell xmllint --xpath 'string(/addon/@version)' addon.xml)
git_branch = $(shell git rev-parse --abbrev-ref HEAD)
git_hash = $(shell git rev-parse --short HEAD)
matrix = $(findstring $(shell xmllint --xpath 'string(/addon/requires/import[@addon="xbmc.python"]/@version)' addon.xml), $(word 1,$(KODI_PYTHON_ABIS)))

ifdef release
	zip_name = $(name)-$(version).zip
else
	zip_name = $(name)-$(version)-$(git_branch)-$(git_hash).zip
endif

include_files = addon.xml changelog.txt default.py LICENSE.txt README.md lib/ resources/
include_paths = $(patsubst %,$(name)/%,$(include_files))
exclude_files = \*.new \*.orig \*.pyc \*.pyo
zip_dir = $(name)/

languages = $(filter-out en_gb, $(patsubst resources/language/resource.language.%, %, $(wildcard resources/language/*)))

blue = \e[1;34m
white = \e[1;37m
reset = \e[0;39m

all: check test build
zip: build
test: check test-unit test-run

check: check-tox check-pylint check-translations

check-tox:
	@echo -e "$(white)=$(blue) Starting sanity tox test$(reset)"
	$(PYTHON) -m tox -q

check-pylint:
	@echo -e "$(white)=$(blue) Starting sanity pylint test$(reset)"
	$(PYTHON) -m pylint -e useless-suppression lib/ tests/

check-translations:
	@echo -e "$(white)=$(blue) Starting language test$(reset)"
	@-$(foreach lang,$(languages), \
		msgcmp --use-untranslated resources/language/resource.language.$(lang)/strings.po resources/language/resource.language.en_gb/strings.po; \
	)

check-untranslated:
	@echo -e "$(white)=$(blue) Starting language test$(reset)"
	@-$(foreach lang,$(languages), \
		msgcmp resources/language/resource.language.$(lang)/strings.po resources/language/resource.language.en_gb/strings.po; \
	)

check-addon: clean
	@echo -e "$(white)=$(blue) Starting sanity addon tests$(reset)"
	kodi-addon-checker . --branch=krypton
	kodi-addon-checker . --branch=leia

kill-proxy:
	-pkill -ef '$(PYTHON) -m proxy'


unit: test-unit

test-unit: clean kill-proxy
	@echo -e "$(white)=$(blue) Starting unit tests$(reset)"
	-$(PYTHON) -m proxy --hostname 127.0.0.1 --log-level DEBUG &
	$(PYTHON) -m unittest discover -v
	pkill -ef '$(PYTHON) -m proxy'

test-run:
	@echo -e "$(white)=$(blue) Run CLI$(reset)"
	$(PYTHON) default.py

build: clean
	@echo -e "$(white)=$(blue) Building new package$(reset)"
	@rm -f ../$(zip_name)
	cd ..; zip -r $(zip_name) $(include_paths) -x $(exclude_files)
	@echo -e "$(white)=$(blue) Successfully wrote package as: $(white)../$(zip_name)$(reset)"

multizip: clean
	@-$(foreach abi,$(KODI_PYTHON_ABIS), \
		echo "cd /addon/requires/import[@addon='xbmc.python']/@version\nset $(abi)\nsave\nbye" | xmllint --shell addon.xml; \
		matrix=$(findstring $(abi), $(word 1,$(KODI_PYTHON_ABIS))); \
		if [ $$matrix ]; then version=$(version)+matrix.1; else version=$(version); fi; \
		echo "cd /addon/@version\nset $$version\nsave\nbye" | xmllint --shell addon.xml; \
		make zip; \
	)

clean:
	@echo -e "$(white)=$(blue) Cleaning up$(reset)"
	find . -name '*.py[cod]' -type f -delete
	find . -name '__pycache__' -type d -delete
	find tests/userdata/ -mindepth 1 -not -name '*settings.json' -delete
	rm -rf .pytest_cache/ .tox/ lib/inputstreamhelper.egg-info/
	rm -f *.log
