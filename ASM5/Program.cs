using System;
using System.Windows.Forms;

namespace ASM5
{

    /* Milestones:
        January 2nd 2026 - Skeleton of program created: Two DLLs loaded dynamically into
    C# program, can load a bitmap image and alter it with the C++ DLL's function.
        January 5th 2026 - C++ blur implemented, needs multithreading.
        January 7th 2026 - Multithreading implemented.
        January 16th 2026 - Finally implemented horizontal blur in assembly
        January 17th 2026 - Horizontal blur made more readable, vertical blur in assembly started; Switching DLL at runtime implemented; Made blur DLL-agnostic. 
        January 18th 2026 - Vertical blur in assembly completed; Tested and debugged assembly blurs. ASM output matches C++ output byte-for-byte.
        January 20th 2026 - Final quality pass before submitting project, now logging results to UI, not just console.
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
