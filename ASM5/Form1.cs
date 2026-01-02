using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Drawing.Imaging;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace ASM5
{
    public partial class Form1: Form
    {
        Bitmap InputBitmap;
        public Form1()
        {
            InitializeComponent();
        }

        private void groupBox2_Enter(object sender, EventArgs e)
        {

        }

        private void pictureBox1_Click(object sender, EventArgs e)
        {

        }

        private void label4_Click(object sender, EventArgs e)
        {

        }

        private void label5_Click(object sender, EventArgs e)
        {

        }

        private void tableLayoutPanel2_Paint(object sender, PaintEventArgs e)
        {

        }

        private void label3_Click(object sender, EventArgs e)
        {

        }

        private void radioButton1_CheckedChanged(object sender, EventArgs e)
        {

        }

        private void radioButton3_CheckedChanged(object sender, EventArgs e)
        {

        }

        private void radioButton3_CheckedChanged_1(object sender, EventArgs e)
        {

        }

        private void label7_Click(object sender, EventArgs e)
        {

        }

        private void button1_Click(object sender, EventArgs e)
        {
            OpenFileDialog ofd = new OpenFileDialog();
            ofd.Filter = "Image Files|*.jpg;*.png;*.bmp;*.gif";

            if (ofd.ShowDialog() == DialogResult.OK)
            {
                InputBitmap = new Bitmap(ofd.FileName);
                pictureInput.Image = InputBitmap;
                LabelFile.Text = ofd.FileName;
            }
            
        }

        private void InputKernel_ValueChanged(object sender, EventArgs e)
        {
            var nud = (NumericUpDown)sender;

            int value = (int)nud.Value;

            if (value % 2 == 0)
            {
                nud.Value = value + 1;   
            }
        }

        [DllImport(@"C:\Users\mkowa\source\repos\ASM5\x64\Debug\gauss_cpp.dll")]
        static extern void gauss(IntPtr data, int depth, int height, int stride);
        private void buttonCpp_Click(object sender, EventArgs e)
        {
            Bitmap output = InputBitmap;
            Rectangle rect = new Rectangle(0, 0, output.Width, output.Height);
            BitmapData data = output.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            // run
            //pass: pointer to data, bit depth, height, stride, eventually where each threads data stops
            gauss(data.Scan0, 4, output.Height, data.Stride);
            output.UnlockBits(data);
            pictureOutput.Image = output;
        }
    }
}
