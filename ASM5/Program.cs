using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace ASM5
{
    static class Program
    {
        [DllImport(@"C:\Users\mkowa\source\repos\ASM5\x64\Debug\asm.dll")]
        static extern int MyProc1(int a, int b);

        [DllImport(@"C:\Users\mkowa\source\repos\ASM5\x64\Debug\gauss_cpp.dll")]
        static extern int sq(int num);

   

        /// <summary>
        /// The main entry point for the application.
        /// </summary>
        [STAThread]
        static void Main()
        {
            int x = 5, y = 3;
            int retVal = MyProc1(x, y);
            int retval2 = sq(2);
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new Form1());
        }
    }
}
