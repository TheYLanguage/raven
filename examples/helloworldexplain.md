[Hello World](HelloWorld.raven)

```nim
mod HelloWorld;

import "std:fmt";

proc : HelloWorld() {
  fmt.println("Hello World");
}
```
This example makes a module named “HelloWorld”, imports the format module from the standard library,
and makes a procedure/function named HelloWorld(). This procedure contains the main code which will be executed by Raven.
This procedure is also the main entry point.
