using System;
using System.Windows.Forms;

namespace ASM5
{

    /*
        January 2nd 2026 - Skeleton of program created: Two DLLs loaded dynamically into
    C# program, can load a bitmap image and alter it with the C++ DLL's function.
        January 5th 2026 - C++ blur implemented, needs multithreading.
     */

    static class Program
    {




        /// <summary>
        /// The main entry point for the application.
        /// </summary>
        [STAThread]
        static void Main()
        {

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new Form1());
        }
    }
}
