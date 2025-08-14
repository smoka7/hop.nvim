# run tests located at «lua/tests/» (files named *_spec.lua)
TESTS_INIT=tests/minimal_init.lua
TESTS_DIR=tests/
PROFILE_DIR=tests/profile/

.PHONY: test profile

test:
	nvim  --headless --noplugin -u ${TESTS_INIT} -c "PlenaryBustedDirectory ${TESTS_DIR} { minimal_init = '${TESTS_INIT}' }"

profile:
	@nvim --headless --noplugin -u  ${PROFILE_DIR}init.lua -V1 -l '${PROFILE_DIR}setup.lua'
	@nvim --headless --noplugin -u  ${PROFILE_DIR}init.lua -V1 -l '${PROFILE_DIR}setup_mappings.lua'
