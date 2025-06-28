# cccpu  
## CPU Core Control Power Utility
![image](https://github.com/user-attachments/assets/4a6111d8-ec2e-4a45-841b-4d0d7ab75c34)

### View and manage the status and power policies of CPU cores.
![image](https://github.com/user-attachments/assets/054bbd46-9df2-4e50-aa8b-063a8cce94a9)
### Finally some XTerm-256 goodness! 

  

## USAGE:
    cccpu.sh [action_flags] [display_flags]
###  No Flags:                   Displays the current status of all cores (default).

## ACTION FLAGS (can be combined):
    --on            [<cores>]    Enables cores. Defaults to 'all' if no list is given.
    --off           [<cores>]    Disables cores. Defaults to all except core 0.
    -g, --governor  <name|list>  Sets governor or lists available governors.
    -b, --bias      <name|list>  Sets bias or lists available biases.
    -c, --cores     <cores>      Target for -g/-b flags. Defaults to all online cores.
    -h, --help                   Shows this help message.

## DISPLAY FLAGS:
    -G, --grid                   Only displays the CPU Core Status grid.
    -T, --table                  Only displays the Detailed Core Status table.

## CORE SPECIFICATION <cores>:
    A list in the format: 1-3,7 or all


The output is pretty easy to follow, and the online cores can be scripted as an enumerated space-separated list. It detects non-interactive and prints: 

    Verified online cores:
    0 1 2 3 4 5 6 7 8 9 10 11


## It also prints a B/W ascii table:

    +===================================================================+
    |                       Detailed Core Status                        |
    +===================================================================+
    |    NODE    |   STATUS   |   GOVERNOR    |          BIAS           |
    +-------------------------------------------------------------------+
    |   Core 0   |   ONLINE   |   powersave   |   balance_performance   |
    |   Core 1   |   ONLINE   |   powersave   |   balance_performance   |
    |   Core 2   |   ONLINE   |   powersave   |   balance_performance   |
    |   Core 3   |   ONLINE   |   powersave   |   balance_performance   |
    |   Core 4   |   ONLINE   |   powersave   |       performance       |
    |   Core 5   |   ONLINE   |   powersave   |       performance       |
    |   Core 6   |   ONLINE   |   powersave   |       performance       |
    |   Core 7   |   ONLINE   |   powersave   |       performance       |
    |   Core 8   |   ONLINE   |   powersave   |       performance       |
    |   Core 9   |   ONLINE   |   powersave   |       performance       |
    |   Core 10  |   ONLINE   |   powersave   |       performance       |
    |   Core 11  |   ONLINE   |   powersave   |       performance       |
    +===================================================================+

