load 'test/libs/bats-support/load'
load 'test/libs/bats-assert/load'
load 'test/libs/helpers/helpers'

# pre-actions before test cases running
setup () {
  export AWS_REGION="us-east-1"
  export ENV="test"
  export test_aws_profile_name="bats_profile"
  export AWS_PROFILE="${test_aws_profile_name}"
  
  # create a temporary folder
  export BATS_TEMP_DIR="/tmp/$(date +%s)"
  mkdir "${BATS_TEMP_DIR}"
  # create AWS creds stub
  create_aws_creds "${BATS_TEMP_DIR}" "${test_aws_profile_name}"
}

# post-actions after tests complete
teardown () {
  # clean-up after tests
  rm -rf ${BATS_TEMP_DIR}
}

# Test cases
@test "Testing ssh tunnel to AWS: should be successful" {
  # initialize all inputs which are used as make rule arguments
  export arg1="arg1 value" 
  export arg2="arg2 value"
  export VAR1="value1"
  export VAR2="value2"

  # create temp Makefie
  create_makefile "${BATS_TEMP_DIR}" \
    '<RULE or MACROS> <arg1> <arg2> ...'

  # Optional part
  # stubs or mocks can be added below


  # Run TEST target 
  run make TEST
  
  # compare result with expected values..
  # can be invoked many times, each from new line    
  assert_success
  
}
