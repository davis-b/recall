# recall #

## What is _recall?_ ##


_recall_ is a Linux program allows you to repeatedly search through another process's memory for a potentially changing value, eventually returning the memory address your specified value is located at. This type of program is known as a _memory scanner_.

_recall_ is written in Zig, and has been designed for zig version 0.7.1.

- - -

### How to use _recall_ ###

1. Call recall with the pid of the program you would like to look through the memory of, and a type + bit length.  
Example:
`recall "$(pidof -s firefox)" i32`
2. Enter a value in order to narrow down memory addresses.
3. Modify the state of the other program.
4. Repeat from step 2 until you have single memory address.


### Notes about type hints and bit lengths ###

Type and bit length must be given to _recall_ together with no characters between the two.

The available types are  
i : signed integer  
u : unsigned integer  
f : float  
s : string  

Strings do not use a bit length, as they can change in length during the normal use of this program.  
Integers can use bit lengths of (8, 16, 32, 64).  
Floats can use bit lengths of (16, 32, 64).  

- - -

## How _recall_ works ##

_recall_ starts by reading a pid's /proc/(pid)/maps file to discover the program's current memory address segments. Some segments are ignored, such as any segment created by something in '/dev/'.

Next, it asks the user for a value; _recall_ converts the given string to the type we are searching for; finally that value gets converted to its byte representation.

It scans through all the available addresses within the memory segments. Any address containing the value that the user just supplied gets stored, as it has the potential to be the single address we are looking for.

From here, we ask for a value and remove (from our potential addresses) any address that does not contain that value. We continue this step until there are 1 or 0 addresses left.

Note: During the final step, it is expected that the user change the state of the program that is being monitored. State change is required to reduce the set of potential addresses.


- - -

## Building ##

With a zig compiler around version 0.7.1, the process should be as simple as cloning this repo, cd'ing into the recall directory, and calling `zig build`

This program has no dependencies beyond the Linux kernel. Linking to C is optional.

The binary produced will be statically linked if not linked to C.
