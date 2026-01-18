using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace ASM5
{
    public partial class Form1 : Form
    {
        Bitmap InputBitmap;


        public Form1()
        {
            InitializeComponent();
        }

        static class NativeLoader

        {
            unsafe delegate void GaussHorizontalDelegate(byte* input, byte* output, int width, int stride, ushort* kernel, int kernel_size, int start_row, int end_row);
            unsafe delegate void GaussVerticalDelegate(byte* input, byte* output, int width, int stride, ushort* kernel, int kernel_size, int start_row, int end_row, int height);

            [DllImport("kernel32")]
            static extern IntPtr LoadLibrary(string lpFileName);

            [DllImport("kernel32")]
            static extern IntPtr GetProcAddress(IntPtr hModule, string procName);

            static IntPtr _dll;
            static GaussHorizontalDelegate _gauss_horizontal;
            static GaussVerticalDelegate _gauss_vertical;

            public static void LoadLib(int lib)
            {
                string path;

                if (lib == 1)
                    path = "./asm.dll";
                else
                    path = "./gauss_cpp.dll";

                _dll = LoadLibrary(path);
                if (_dll == IntPtr.Zero)
                    throw new Exception("Failed to load DLL");

                IntPtr fn = GetProcAddress(_dll, "gauss_horizontal");
                if (fn == IntPtr.Zero)
                    throw new Exception("Function not found");

                _gauss_horizontal = Marshal.GetDelegateForFunctionPointer<GaussHorizontalDelegate>(fn);

                 fn = GetProcAddress(_dll, "gauss_vertical");
                if (fn == IntPtr.Zero)
                    throw new Exception("Function not found");
                _gauss_vertical = Marshal.GetDelegateForFunctionPointer<GaussVerticalDelegate>(fn);
            }

            public static unsafe void gauss_horizontal(byte* input, byte* output, int width, int stride, ushort* kernel, int kernel_size, int start_row, int end_row)
            {
                _gauss_horizontal(input, output, width, stride, kernel, kernel_size, start_row, end_row);
            }
            public static unsafe void gauss_vertical(byte* input, byte* output, int width, int stride, ushort* kernel,int kernel_size, int start_row, int end_row, int height)
            {
                _gauss_vertical(input, output, width, stride, kernel, kernel_size, start_row, end_row, height);
            }
        }
        private void button1_Click(object sender, EventArgs e)
        {
            OpenFileDialog ofd = new OpenFileDialog();
            ofd.Filter = "Image Files|*.jpg;*.png;*.bmp;";

            if (ofd.ShowDialog() == DialogResult.OK)
            {
                InputBitmap = new Bitmap(ofd.FileName);
                pictureInput.Image = InputBitmap;
                LabelFile.Text = ofd.FileName;

            }

        }

        ushort[] generate_gaussian_kernel(float sigma, int kernel_radius)
        {
            ushort[] kernel_result = new ushort[kernel_radius];
            int[] kernel = new int[kernel_radius];
            float[] temp_kernel = new float[kernel_radius];
            float sum = 0;
            temp_kernel[0] = gaussian_distribution(0, sigma);
            sum += temp_kernel[0];
            for (int i = 1; i < kernel_radius; i++)
            {
                float v = gaussian_distribution(i, sigma);
                temp_kernel[i] = v;
                sum += 2 * v;
            }
            ushort fixedsum = 0;
            temp_kernel[0] /= sum;
            kernel_result[0] = (ushort)(temp_kernel[0] * (1 << 14));
            fixedsum += (ushort)kernel_result[0];
            for (int i = 1; i < kernel_radius; i++)
            {
                temp_kernel[i] /= sum;
                kernel_result[i] = (ushort)(temp_kernel[i] * (1 << 14));
                fixedsum += (ushort)(2 * kernel_result[i]);
            }
            kernel_result[0] += (ushort)((1 << 14) - fixedsum);
            return kernel_result;
        }
        private void InputKernel_ValueChanged(object sender, EventArgs e)
        {
            var nud = (NumericUpDown)sender;

            int value = (int)nud.Value;

        }
        float gaussian_distribution(int x, float sigma)
        {
            return (float)Math.Exp(-(x * x) / (2 * sigma * sigma));
        }
       
        private void buttonCpp_Click(object sender, EventArgs e)
        {
            NativeLoader.LoadLib(0);
            if (InputBitmap == null)
            {
                MessageBox.Show("Please load an image first.");
                return;
            }
            Stopwatch sw = new Stopwatch();
            sw.Start();
            blur();
            sw.Stop();
            Console.WriteLine("CPP: Elapsed={0}", sw.Elapsed);
            
#if DEBUG
            string exeDir = AppDomain.CurrentDomain.BaseDirectory;
            string filename = $"{Path.GetFileName(LabelFile.Text)}_cpp_debug_sigma={InputSigma.Value}_radius={InputKernel.Value}{DateTime.Now:yyyyMMdd_HHmmss_fff}.png";
            string path = Path.Combine(exeDir, filename);
            pictureOutput.Image.Save(path, ImageFormat.Bmp);
#else
            string exeDir = AppDomain.CurrentDomain.BaseDirectory;
            string filename = $"{Path.GetFileName(LabelFile.Text)}_cpp_release_sigma={InputSigma.Value}_radius={InputKernel.Value}{DateTime.Now:yyyyMMdd_HHmmss_fff}.png";
            string path = Path.Combine(exeDir, filename);
            pictureOutput.Image..Save(path, ImageFormat.Bmp);
#endif
        }



        private void buttonAsm_Click(object sender, EventArgs e)
        {
            NativeLoader.LoadLib(1);
            if (InputBitmap == null)
            {
                MessageBox.Show("Please load an image first.");
                return;
            }
            Stopwatch sw = new Stopwatch();
            sw.Start();
            blur();
            sw.Stop();
            Console.WriteLine("ASM: Elapsed={0}", sw.Elapsed);
#if DEBUG
            string exeDir = AppDomain.CurrentDomain.BaseDirectory;
            string filename = $"{Path.GetFileName(LabelFile.Text)}_asm_debug_sigma={InputSigma.Value}_radius={InputKernel.Value}{DateTime.Now:yyyyMMdd_HHmmss_fff}.png";
            string path = Path.Combine(exeDir, filename);
            pictureOutput.Image.Save(path, ImageFormat.Bmp);
#else
            string exeDir = AppDomain.CurrentDomain.BaseDirectory;
            string filename = $"{Path.GetFileName(LabelFile.Text)}_asm_release_sigma={InputSigma.Value}_radius={InputKernel.Value}{DateTime.Now:yyyyMMdd_HHmmss_fff}.png";
            string path = Path.Combine(exeDir, filename);
            pictureOutput.Image..Save(path, ImageFormat.Bmp);
#endif
        }
       
        void blur()
        {
            Cursor.Current = Cursors.WaitCursor;

            Rectangle rect = new Rectangle(0, 0, InputBitmap.Width, InputBitmap.Height);


            BitmapData data = InputBitmap.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            byte[] image = new byte[data.Height * data.Stride];
            Marshal.Copy(data.Scan0, image, 0, image.Length);
            int stride = data.Stride;
            int height = data.Height;
            int width = data.Width;
            InputBitmap.UnlockBits(data);
            progressBar.Value = 0;

            int kernel_size = (int)InputKernel.Value;
            ushort[] kernel = generate_gaussian_kernel((float)InputSigma.Value, kernel_size);
            int thread_count = (int)InputThreads.Value;
            int slice_height = InputBitmap.Height / thread_count;
            Thread[] threads = new Thread[thread_count];
            progressBar.Maximum = 2 * thread_count + 1;

            byte[] temp = new byte[height * stride];


            unsafe
            {
                ushort* p_kernel;
                byte* p_temp, p_image;
                fixed (ushort* fixed_kernel = kernel)
                fixed (byte* fixed_image = image)

                {
                    fixed (byte* fixed_temp = temp)
                    {
                        p_temp = fixed_temp;
                        p_kernel = fixed_kernel;
                        p_image = fixed_image;
                        for (int i = 0; i < thread_count; i++)
                        {
                            int start_row = i * slice_height;
                          
                            int end_row = (i == thread_count - 1) ? height : start_row + slice_height;
                            threads[i] = new Thread(() =>
                            {
                                 NativeLoader.gauss_horizontal(p_image, p_temp, width, stride, p_kernel, kernel_size, start_row, end_row);
                                return;
                            });
                            threads[i].Start();

                        }


                        for (int i = 0; i < thread_count; i++)
                        {
                            threads[i].Join();
                            progressBar.Value += 2;
                            progressBar.Value -= 1;




                        }

                        for (int i = 0; i < thread_count; i++)
                        {
                            int start_row = i * slice_height;
                            int end_row = (i == thread_count - 1) ? InputBitmap.Height : start_row + slice_height;
                            threads[i] = new Thread(() =>
                            {
                                NativeLoader.gauss_vertical(p_temp, p_image , width, stride, p_kernel, kernel_size, start_row, end_row, height);
                            });
                            threads[i].Start();
                        }

                        for (int i = 0; i < thread_count; i++)
                        {
                            threads[i].Join();
                            progressBar.Value += 2;
                            progressBar.Value -= 1;
                        }

                        progressBar.Maximum = 2 * thread_count;
                    }
                }
            }

            Bitmap output = new Bitmap(width, height, PixelFormat.Format32bppArgb);

            data = output.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            Marshal.Copy(image, 0, data.Scan0, image.Length); //! CHANGE BACK TO IMAGE!
            output.UnlockBits(data);
            if (pictureOutput.Image != null)
            {
                var old = pictureOutput.Image;
                pictureOutput.Image = null;
                old.Dispose();
            }
            pictureOutput.Image = output;
            Cursor.Current = Cursors.Arrow;

        }
    }
}
