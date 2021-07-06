# This implementation is a faithful implementation in riscv64 assembly.
# It can be used for sieve sizes up to 100,000,000; beyond that some register widths used will become too narrow.
.option pic

.global main

.extern printf
.extern malloc
.extern free

            .struct 0
time_sec:   
            .struct     time_sec + 8
time_fract: 
            .struct     time_fract + 8
time_size:

            .struct     0
sieve_arraySize:    
            .struct     sieve_arraySize + 4
sieve_primes:       
            .struct     sieve_primes + 8
sieve_size:

.equ        SIEVE_LIMIT,    1000000     # sieve size
.equ        RUNTIME,        5           # target run time in seconds
.equ        FALSE,          0           # false constant
.equ        NULL,           0           # null pointer

.equ        CLOCK_GETTIME,  113         # syscall number for clock_gettime
.equ        CLOCK_MONOTONIC,1           # CLOCK_MONOTONIC
.equ        WRITE,          64          # syscall number for write
.equ        STDOUT,         1           # file descriptor of stdout

.equ        MILLION,        1000000
.equ        BILLION,        1000000000


.data

.balign     8

refResults:
.word       10, 4
.word       100, 25
.word       1000, 168
.word       10000, 1229
.word       100000, 9592
.word       1000000, 78498
.word       10000000, 664579
.word       100000000, 5761455
.word       0

.balign     4

startTime:                              # start time of sieve run
.skip       time_size                           

.balign     4

duration:                               # duration
.skip       time_size                           

.balign     4

outputFmt:                              # format string for output
.asciz      "ctopper_risv64_byte;%d;%d.%03d;1;algorithm=base,faithful=yes,bits=8\n"   

.balign     4

incorrect:                              # incorrect result warning message
.asciz      "WARNING: result is incorrect!\n"

.equ        incorrectLen, . - incorrect # length of previous

.text

main:
    addi    sp, sp, -16
    sd      ra, 8(sp)     # push ra on stack

# registers (global variables)
# * s5: billion
# * s7: sieveSize
# * s8: runCount
# * s9: sievePtr (&sieve)
# * s10: sizeSqrt
# * s11: initBlock

    li      s11, 0x0101010101010101 # init pattern

    li      s7, BILLION             # billion = BILLION

    li      s8, 0                   # runCount = 0

    li      s7, SIEVE_LIMIT         # sieveSize = sieve size

    fcvt.s.lu fa0, s7               # fa0 = sizeSieve
    fsqrt.s   fa0, fa0              # fa0 = sqrt(fa0)
    fcvt.lu.s s10, fa0              # sizeSqrt = fa0
    addi      s10, s10, 1           # sizeSqrt++, for safety

# get start time
    li      a7, CLOCK_GETTIME
    li      a0, CLOCK_MONOTONIC
    lla     a1, startTime
    ecall

    li      s9, 0                   # sievePtr = null

runLoop:
    beqz    s9, createSieve         # if sievePtr == null then skip deletion

    mv      a0, s9                  # pass sievePtr
    call    deleteSieve             # delete sieve

createSieve:
    mv      a0, s7                  # pass sieve size
    call    newSieve                # a0 = & sieve

    mv      s9, a0                  # sievePtr = x0

    call    runSieve                # run sieve

# registers:
# * a0: numDurationSeconds
# * a1: numDurationNanoseconds/numDurationMilliseconds
# * a2: startTimePtr
# * a3: numStartTimeSeconds/numStartTimeNanoseconds
# * s6: durationPtr

    li      a7, CLOCK_GETTIME
    li      a0, CLOCK_MONOTONIC
    lla     a1, duration
    ecall

    lla     a2, startTime # startTimePtr = &startTime
    lla     s6, duration # durationPtr = &duration

    ld      a0, time_sec(s6)
    ld      a3, time_sec(a2)
    sub     a0, a0, a3

    ld      a1, time_fract(s6)
    ld      a3, time_fract(a2)
    sub     a1, a1, a3

    bgez    a1, checkTime  # if numNanoseconds >= 0 then check the duration...
    addi    a0, a0, -1     # ...else numSeconds --...
    add     a1, a1, s5    # ...and numNanoSeconds += billion
checkTime:
    add     s8, s8, 1    # runCount++
    li      a3, RUNTIME
    bltu    a0, a3, runLoop

# we're pass the 5 second mark, so it's time to store the exact duration of our runs   
    sd      a0, time_sec(s6)

    li      a2, MILLION             # a2 = 1,000,000
    divu    a1, a1, a2              # a1 /= a2, so a2 contains numMilliseconds

    sd      a1, time_fract(s6)      # duration.fraction = numMilliseconds

# let's count our primes
    mv      a0, s9                  # pass sievePtr
    call    countPrimes             # a0 = primeCount

    lla     a1, refResults          # refResultPtr = (int *)&refResults

checkLoop:
    lw      a2, (a1)                # curSieveSize = *refResultPtr
    beqz    a2, printWarning        # if curSieveSize == 0 then we didn't find our sieve size, so warn about incorrect result
    beq     a2, s7, checkValue      # if curSieveSize == sieveSize check the reference result value
    addi    a1, a1, 8               # else refResultsPtr +=2
    j       checkLoop               # keep looking for sieve size
    
checkValue:
    lwu     a2, 4(a1)               # curResult = *(refResultPtr + 1)
    beq     a2, a0, printResults    # if curResult == primeCount print result

# if we're here, something's amiss with our outcome
printWarning:
    li      a7, WRITE               # syscall to make, parameters:
    li      a0, STDOUT              # * write to stdout
    lla     a1, incorrect           # * message is warning
    li      a2, incorrectLen        # * length of message
    ecall

printResults:
    lla     a0, outputFmt
    mv      a1, s8
    lla     s6, duration
    ld      a2, time_sec(s6)   
    ld      a3, time_fract(s6)   
    call    printf@plt

    li      a0, 0
    ld      ra, 8(sp)
    addi    sp, sp, 16
    ret

# parameters:
# * a0: sieve limit
# returns:
# * a0: &sieve
newSieve:
    addi    sp, sp, -16
    sd      ra, 8(sp)

    mv      s3, a0                  # keep parameter, we'll need it later

    li      a0, sieve_size          # ask for sieve size bytes
    call    malloc@plt              # a0 = &sieve

    mv      s4, a0                  # sievePtr = x0

    addi    s3, s3, 1               # array_size = sieve limit + 1
    srli    s3, s3, 1               # array_size /= 2
    sw      s3, sieve_arraySize(a0) # sieve.arraySize = array_size

    srli    s3, s3, 3               # initBlockCount /= 8
    addi    s3, s3, 1               # initBlockCount++

    mv      a0, s3                  # initBlockBytes = initBlockCount
    slli    a0, a0, 3               # initBlockBytes *= 8
    call    malloc@plt              # x0 = &array[0]

    sd      a0, sieve_primes(s4)

# initialize prime array
    li      a1, 0                   # initBlockIndex = 0

initLoop:
    sd      s11, (a0)               # sieve.primes[initBlockPtr..initBlockPtr+8] = true;
    addi    a0, a0, 8               # initBlockPtr += 8
    addi    a1, a1, 1               # initBlockIndex++
    bne     a1, s3, initLoop        # if initBlockIndex < initBlockCount

    mv      a0, s4                  # return sievePtr

    ld      ra, 8(sp)
    addi    sp, sp, 16
    ret

# parameters:
# *a0: sievePtr (&sieve)
deleteSieve:
    addi    sp, sp, -16
    sd      ra, 8(sp)

    mv      s3, a0                  # keep sievePtr, we'll need it later

    ld      a0, sieve_primes(s3)    # ask to free sieve.primes
    call    free@plt

    mv      a0, s3                  # ask to free sieve
    call    free@plt

    ld      ra, 8(sp)
    addi    sp, sp, 16
    ret

# parameters:
# * a0: sievePtr (&sieve)
# returns:
# * &sieve_primes[0]
runSieve:

# registers:
# * a1: primesPtr (&sieve_primes[0])

    ld      a1, sieve_primes(a0)        # primesPtr = &sieve.primes[0]
    li      a3, 3                       # factor = 3
    lwu     a5, sieve_arraySize(a0)     # arraySize = sieve.arraySize

sieveLoop:
    mul     a2, a3, a3                  # arrayIndex = factor * factor
    srli    a2, a2, 1                   # arrayIndex /= 2

# clear multiples of factor
unsetLoop:
    add     a4, a1, a2
    sb      x0, 0(a4)                   # sieve.primes[arrayIndex] = false
    add     a2, a2, a3                  # arrayIndex += factor
    bltu    a2, a5, unsetLoop           # if arrayIndex < arraySize continue marking non-primes

    mv      a2, a3                      # arrayIndex = factor
    srli    a2, a2, 1                   # arrayIndex /= 2

# find the next factor
factorLoop:
    add     a3, a3, 2                   # factor += 2
    bgtu    a3, s10, endRun             # if factor > sizeSqrt end this run

    addi    a2, a2, 1                   # arrayIndex++

    add     a4, a1, a2
    ld      a6, 0(a4)                   # curPrime = sieve.primes[arrayIndex]
    bnez    a6, sieveLoop               # if curPrimte then continue run
    j       factorLoop                  # continue looking

endRun:
    mv      a0, a1                      # return &sieve.primes[0]

    ret                                 # end of runSieve

# parameters:
# * a0: sievePtr (&sieve)
# returns:
# * primeCount
countPrimes:
    lwu     a1, sieve_arraySize(a0)     # arraySize = sieve.arraySize
    ld      a2, sieve_primes(a0)        # primesPtr = &sieve.primes[0]
    li      a0, 1                       # primeCount = 1  
    li      a3, 1                       # arrayIndex = 1

countLoop:
    add     a4, a2, a3
    lb      a4, (a4)                    # curPrimte = sieve.primes[arrayIndex]
    beqz    a4, skipinc                 # if curPrime
    addi    a0, a0, 1                   # primeCount++
skipinc:
    addi    a3, a3, 1                   # arrayIndex++
    bltu    a3, a1, countLoop           # if arrayIndex < arraySize continue counting

    ret                                 # end of countPrimes
